import Foundation

public struct DualSenseChecksum {
    private static let table: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB88320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }
    }()
    
    /// Seed byte prefixed to the payload before hashing. The DualSense uses a
    /// different seed per report direction (`PS_*_CRC32_SEED` in the kernel).
    public static let inputSeed: UInt8 = 0xA1
    public static let outputSeed: UInt8 = 0xA2
    public static let featureSeed: UInt8 = 0xA3

    /// Computes the CRC32 checksum specifically for DualSense Bluetooth Output Reports.
    /// In the DualSense Bluetooth protocol, the CRC32 is calculated over a single-byte prefix (0xA2)
    /// followed by the report payload bytes (e.g. bytes 0 through 73 of the 78-byte report).
    public static func computeCRC32(for data: [UInt8], prefix: UInt8 = outputSeed) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        
        // Feed prefix (0xA2)
        crc = table[Int((crc ^ UInt32(prefix)) & 0xFF)] ^ (crc >> 8)
        
        // Feed buffer bytes
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        
        return ~crc
    }
    
    /// Computes the CRC32 over a raw buffer without copying it.
    ///
    /// Input reports arrive in the hundreds per second, so the checksum path
    /// must not allocate a fresh Array for every packet.
    public static func computeCRC32(
        for buffer: UnsafeBufferPointer<UInt8>,
        count: Int,
        prefix: UInt8
    ) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        crc = table[Int((crc ^ UInt32(prefix)) & 0xFF)] ^ (crc >> 8)
        for i in 0..<min(count, buffer.count) {
            crc = table[Int((crc ^ UInt32(buffer[i])) & 0xFF)] ^ (crc >> 8)
        }
        return ~crc
    }

    /// Injects the CRC32 checksum into the final 4 bytes of a Bluetooth output report.
    public static func appendBluetoothCRC(to report: inout [UInt8]) {
        guard report.count == DualSenseProtocol.outputReportSizeBT else { return }
        let crcOffset = report.count - 4
        let crc = computeCRC32(for: Array(report[0..<crcOffset]), prefix: outputSeed)

        report[crcOffset] = UInt8(crc & 0xFF)
        report[crcOffset + 1] = UInt8((crc >> 8) & 0xFF)
        report[crcOffset + 2] = UInt8((crc >> 16) & 0xFF)
        report[crcOffset + 3] = UInt8((crc >> 24) & 0xFF)
    }
}
