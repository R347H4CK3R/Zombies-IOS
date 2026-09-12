import XCTest
@testable import ZombiesIOS

final class T6ZonePointerTests: XCTestCase {
    func testRoundTripUsesThreeHighBlockBitsAndTwentyNineOffsetBits() throws {
        let serialized = try XCTUnwrap(T6ZonePointer.encode(blockIndex: 5, blockOffset: 0x0012_3456))
        let pointer = try XCTUnwrap(T6ZonePointer(serializedValue: serialized))

        XCTAssertEqual(pointer.blockIndex, 5)
        XCTAssertEqual(pointer.blockOffset, 0x0012_3456)
    }

    func testSerializedValueIsOffsetByOneSoBlockZeroOffsetZeroIsNotNull() throws {
        XCTAssertEqual(T6ZonePointer.encode(blockIndex: 0, blockOffset: 0), 1)
        let pointer = try XCTUnwrap(T6ZonePointer(serializedValue: 1))
        XCTAssertEqual(pointer.blockIndex, 0)
        XCTAssertEqual(pointer.blockOffset, 0)
        XCTAssertNil(T6ZonePointer(serializedValue: 0))
    }

    func testResolverRejectsOffsetOutsideDeclaredBlockSize() throws {
        let resolver = T6ZonePointerResolver(blockSizes: [16, 32, 64, 128, 256, 512, 1024, 2048])
        let serialized = try XCTUnwrap(T6ZonePointer.encode(blockIndex: 2, blockOffset: 64))

        XCTAssertThrowsError(try resolver.decode(serialized)) { error in
            XCTAssertEqual(
                error as? T6ZonePointerResolver.ResolveError,
                .offsetOutsideBlock(block: 2, offset: 64, size: 64)
            )
        }
    }
}
