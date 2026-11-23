enum Fixtures {
    /// Real `i` reply from Brian's Bus Pirate 5 REV10 on 2026-11-23, after the firmware update.
    static let infoReply = """
    Bus Pirate 5 REV10
    https://BusPirate.com/
    Firmware main branch @ e9cb31e (Nov 20 2026 08:39:34)
    RP2040 with 264KB RAM, 128Mbit FLASH
    S/N: 0000000000000000
    Storage: 0.10GB Micron (FAT16 File System)
    Terminal: 80x25

    Configuration file: Not Detected
    Active binmode: SUMP logic analyzer
    Available modes: HiZ 1WIRE UART HDUART I2C SPI 2WIRE 3WIRE DIO LED INFRARED JTAG PS2 USB
    Active mode: HiZ

    Display format: Auto
    """

    /// Real `i` reply from the factory firmware.
    static let oldInfoReply = """
    Bus Pirate 5 REV10
    Firmware v0.1.0 (commit unknown)
    RP2040 with 264KB RAM, 128Mbit FLASH
    S/N: 0000000000000000
    https://BusPirate.com/
    Storage:   0.10GB (FAT16 File System)

    Configuration file: Not Detected
    Available modes: HiZ 1-WIRE UART I2C SPI LED
    Active mode: HiZ ()=()
    Display format: Auto
    """
}
