/// Pure-Dart lens/frame recommendation logic.
/// Inputs come from the latest Rx and optionally face-shape input.
/// Output is a structured `Recommendation` displayed in the report screen.
library;

class Recommendation {
  final String material;       // BLANCO, POLI, HI
  final String design;         // MONO, BIFOCAL, PROGRESIVO
  final String arCoating;      // NO, AR, AR_BLUE
  final bool photochromicSuggested;
  final List<String> frameShapes; // e.g. ['Redondo', 'Rectangular']
  final List<String> reasons;

  const Recommendation({
    required this.material,
    required this.design,
    required this.arCoating,
    required this.photochromicSuggested,
    required this.frameShapes,
    required this.reasons,
  });
}

/// Face shapes supported by the matching matrix.
enum FaceShape { round, oval, square, heart, oblong, diamond }

const _faceShapeFrames = <FaceShape, List<String>>{
  FaceShape.round: ['Rectangular', 'Cuadrado', 'Aviator'],
  FaceShape.oval: ['Cualquier estilo', 'Wayfarer', 'Aviator'],
  FaceShape.square: ['Redondo', 'Ovalado', 'Cat-eye'],
  FaceShape.heart: ['Aviator', 'Rectangular bajo', 'Sin marco'],
  FaceShape.oblong: ['Cuadrado ancho', 'Decorativo'],
  FaceShape.diamond: ['Cat-eye', 'Oval', 'Sin marco'],
};

class RecommendationEngine {
  static Recommendation forRx({
    required double? odEsf,
    required double? oiEsf,
    required double? odAdd,
    required double? oiAdd,
    required int age,
    FaceShape? face,
    bool diabetes = false,
  }) {
    final reasons = <String>[];
    // Highest absolute spherical power
    final maxAbs =
        [odEsf, oiEsf].whereType<double>().fold<double>(0, (s, v) => v.abs() > s ? v.abs() : s);

    // Material
    String material;
    if (maxAbs >= 4) {
      material = 'HI';
      reasons.add('Rx alta (±$maxAbs) → alto índice para reducir grosor.');
    } else if (age < 18 || maxAbs >= 2.5) {
      material = 'POLI';
      reasons.add(
          age < 18 ? 'Menor de edad → policarbonato (impacto).' : 'Rx moderada → policarbonato.');
    } else {
      material = 'BLANCO';
      reasons.add('Rx baja → CR-39 estándar.');
    }

    // Design
    String design = 'MONO';
    final hasAdd = (odAdd ?? 0) > 0 || (oiAdd ?? 0) > 0;
    if (hasAdd) {
      if (age >= 45) {
        design = 'PROGRESIVO';
        reasons.add('Presbicia + adición → progresivo.');
      } else {
        design = 'BIFOCAL';
        reasons.add('Adición indicada → bifocal.');
      }
    }

    // AR
    String ar = 'AR';
    reasons.add('AR estándar para reducir reflejos.');
    if (age <= 35) {
      ar = 'AR_BLUE';
      reasons.add('Usuario joven con uso de pantallas → AR + filtro azul.');
    }

    // Photochromic
    final photo = age <= 50 && maxAbs <= 5;
    if (photo) reasons.add('Sugerido fotocromático para uso al aire libre.');

    // Face frames
    final frames = face != null
        ? _faceShapeFrames[face]!
        : const ['Sin preferencia — sugerir según prueba en tienda'];

    if (diabetes) {
      reasons.add('Diabético: recomendar revisión retinal anual.');
    }

    return Recommendation(
      material: material,
      design: design,
      arCoating: ar,
      photochromicSuggested: photo,
      frameShapes: frames,
      reasons: reasons,
    );
  }
}
