/// Resource information read from the connected Android device.
///
/// Null means the device did not report a trustworthy value. Storage refers to
/// the /data filesystem, which holds installed apps and their data.
class DeviceResources {
  final int? ramTotalBytes;
  final int? ramAvailableBytes;
  final int? cpuMaxKhz;
  final int? storageTotalBytes;
  final int? storageUsedBytes;
  final int? storageAvailableBytes;

  const DeviceResources({
    this.ramTotalBytes,
    this.ramAvailableBytes,
    this.cpuMaxKhz,
    this.storageTotalBytes,
    this.storageUsedBytes,
    this.storageAvailableBytes,
  });
}
