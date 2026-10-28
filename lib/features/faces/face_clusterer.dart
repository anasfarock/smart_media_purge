import 'dart:typed_data';

import '../../core/utils/vector_math.dart';

class FaceVec {
  const FaceVec(this.id, this.embedding, this.clusterId);
  final int id;
  final Float32List embedding;
  final int? clusterId;
}

class ClusterOutput {
  const ClusterOutput(this.assignment, this.merged);

  /// faceId -> clusterId. Negative ids are brand-new clusters (DB id still to be created).
  final Map<int, int> assignment;

  /// Existing (positive) clusters that were folded into another one: dropped -> survivor.
  final Map<int, int> merged;
}

/// Incremental centroid clustering on cosine similarity.
///  1. Faces already in a cluster keep it (so names / privacy flags survive re-runs).
///  2. New faces join the closest centroid above [threshold], else start a new cluster.
///  3. A merge pass fuses clusters whose centroids are very close ([threshold] + [mergeMargin]).
/// Embeddings must be L2-normalised. Tune [threshold] for your face model.
class FaceClusterer {
  FaceClusterer({this.threshold = 0.55, this.mergeMargin = 0.08});

  final double threshold;
  final double mergeMargin;

  ClusterOutput run(List<FaceVec> faces) {
    final sums = <int, Float32List>{};
    final norms = <int, double>{};
    final assignment = <int, int>{};

    void add(int c, Float32List e) {
      final s = sums.putIfAbsent(c, () => Float32List(e.length));
      for (var i = 0; i < e.length; i++) {
        s[i] += e[i];
      }
      norms[c] = VectorMath.norm(s);
    }

    for (final f in faces) {
      final c = f.clusterId;
      if (c != null) {
        assignment[f.id] = c;
        add(c, f.embedding);
      }
    }

    var nextTemp = -1;
    for (final f in faces) {
      if (f.clusterId != null) continue;
      int? best;
      var bestSim = -2.0;
      sums.forEach((c, s) {
        final n = norms[c]!;
        if (n == 0) return;
        final sim = VectorMath.dot(s, f.embedding) / n;
        if (sim > bestSim) {
          bestSim = sim;
          best = c;
        }
      });
      final target = best;
      if (target != null && bestSim >= threshold) {
        assignment[f.id] = target;
        add(target, f.embedding);
      } else {
        final c = nextTemp--;
        assignment[f.id] = c;
        add(c, f.embedding);
      }
    }

    // Merge pass
    final merged = <int, int>{};
    var changed = true;
    while (changed) {
      changed = false;
      final ids = sums.keys.toList();
      for (var i = 0; i < ids.length && !changed; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = ids[i], b = ids[j];
          final na = norms[a]!, nb = norms[b]!;
          if (na == 0 || nb == 0) continue;
          final sim = VectorMath.dot(sums[a]!, sums[b]!) / (na * nb);
          if (sim < threshold + mergeMargin) continue;
          final keep = _survivor(a, b);
          final drop = keep == a ? b : a;
          final sk = sums[keep]!, sd = sums[drop]!;
          for (var k = 0; k < sk.length; k++) {
            sk[k] += sd[k];
          }
          norms[keep] = VectorMath.norm(sk);
          sums.remove(drop);
          norms.remove(drop);
          merged[drop] = keep;
          changed = true;
          break;
        }
      }
    }

    int resolve(int c) {
      while (merged.containsKey(c)) {
        c = merged[c]!;
      }
      return c;
    }

    assignment.updateAll((_, c) => resolve(c));
    final positiveMerges = <int, int>{
      for (final e in merged.entries)
        if (e.key > 0) e.key: resolve(e.key),
    };
    return ClusterOutput(assignment, positiveMerges);
  }

  /// Prefer keeping an existing DB cluster (positive id; lowest wins).
  static int _survivor(int a, int b) {
    if (a > 0 && b > 0) return a < b ? a : b;
    if (a > 0) return a;
    if (b > 0) return b;
    return a > b ? a : b;
  }
}
