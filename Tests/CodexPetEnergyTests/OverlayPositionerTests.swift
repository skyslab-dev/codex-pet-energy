import XCTest
@testable import CodexPetEnergy

final class OverlayPositionerTests: XCTestCase {
    func testPlacesOverlayOnRightWhenSpaceExists() {
        let placement = PetPlacement(
            mascotRect: CGRect(x: 100, y: 100, width: 80, height: 87),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let frame = OverlayPositioner.frame(for: CGSize(width: 292, height: 184), beside: placement)
        XCTAssertEqual(frame.minX, 192)
    }

    func testPlacesOverlayOnLeftNearRightEdge() {
        let placement = PetPlacement(
            mascotRect: CGRect(x: 900, y: 100, width: 80, height: 87),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let frame = OverlayPositioner.frame(for: CGSize(width: 292, height: 184), beside: placement)
        XCTAssertEqual(frame.minX, 596)
    }

    func testClampsOverlayInsideTopAndBottomEdges() {
        let panel = CGSize(width: 207, height: 178)
        let screen = CGRect(x: 0, y: 20, width: 800, height: 600)
        let top = OverlayPositioner.frame(
            for: panel,
            beside: PetPlacement(mascotRect: CGRect(x: 100, y: 590, width: 80, height: 87), screenFrame: screen)
        )
        let bottom = OverlayPositioner.frame(
            for: panel,
            beside: PetPlacement(mascotRect: CGRect(x: 100, y: -20, width: 80, height: 87), screenFrame: screen)
        )
        XCTAssertEqual(top.maxY, screen.maxY - 8)
        XCTAssertEqual(bottom.minY, screen.minY + 8)
    }

    func testQuartzToCocoaCoordinateConversionUsesPrimaryScreenTop() {
        let quartz = CGRect(x: -400, y: -200, width: 356, height: 320)
        let cocoa = PetTracker.cocoaRect(fromQuartzRect: quartz, primaryScreenTop: 1_440)
        XCTAssertEqual(cocoa, CGRect(x: -400, y: 1_320, width: 356, height: 320))
    }

    func testReadsPersistedPetState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = """
        {
          "electron-avatar-overlay-open": true,
          "electron-avatar-overlay-bounds": {
            "x": 41, "y": 662, "width": 356, "height": 320,
            "mascot": {"left": 11, "top": 160, "width": 80, "height": 87}
          }
        }
        """
        try Data(json.utf8).write(to: url)
        let state = PetTracker.readPersistedState(from: url)
        XCTAssertEqual(state?.isOpen, true)
        XCTAssertEqual(state?.windowRect, CGRect(x: 41, y: 662, width: 356, height: 320))
        XCTAssertEqual(state?.mascotOffset, CGRect(x: 11, y: 160, width: 80, height: 87))
    }

    func testRejectsIncompletePersistedPetState() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"electron-avatar-overlay-open":true}"#.utf8).write(to: url)
        XCTAssertNil(PetTracker.readPersistedState(from: url))
    }
}
