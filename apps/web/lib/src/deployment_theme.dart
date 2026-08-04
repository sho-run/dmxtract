import 'package:flutter/material.dart';

/// Optional, deployer-owned visual assets.
///
/// The public build keeps this disabled. A self-hosted deployment may provide
/// the documented asset paths and set `DMXTRACT_CUSTOM_THEME=true` at build
/// time without changing DMXtract's behavior or copying private assets here.
abstract final class DeploymentTheme {
  static const enabled = bool.fromEnvironment('DMXTRACT_CUSTOM_THEME');
  static const backgroundAsset = 'assets/deployment/background.png';
  static const manualDropAsset = 'assets/deployment/manual-drop.png';

  static DecorationImage? get background => enabled
      ? const DecorationImage(
          image: AssetImage(backgroundAsset),
          fit: BoxFit.cover,
          opacity: .24,
          colorFilter: ColorFilter.mode(Color(0xff32150e), BlendMode.multiply),
        )
      : null;
}

class DeploymentManualDropMark extends StatelessWidget {
  const DeploymentManualDropMark({super.key, this.large = false});
  final bool large;

  @override
  Widget build(BuildContext context) {
    if (!DeploymentTheme.enabled) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xffa35d3d).withValues(alpha: .2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.file_download_outlined,
          size: 38,
          color: Color(0xffe6a33a),
        ),
      );
    }
    final size = large ? 172.0 : 142.0;
    return Semantics(
      image: true,
      label: 'Manual drop target',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: const DecorationImage(
            image: AssetImage(DeploymentTheme.manualDropAsset),
            fit: BoxFit.contain,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99ffab00),
              blurRadius: 30,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Color(0xcc000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: size * .34,
          height: size * .34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xcc190a08),
          ),
          child: Icon(
            Icons.file_download_outlined,
            size: size * .22,
            color: const Color(0xffffab00),
          ),
        ),
      ),
    );
  }
}
