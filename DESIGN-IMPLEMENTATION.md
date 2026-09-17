# Figma → SwiftUI

Source: https://www.figma.com/design/02QtcO8vWWEtYLzRHgZXgI/?node-id=2-51

Read design context and screenshots for Goal Setup (6:2), Recommended Route (7:51), Running (8:337), Complete (8:299), Loading (26:2).

- ContentView: goal setup, loading, route overview/navigation. Existing distance/pace preferences, RoutePlanner, LocationManager and signal data are reused.
- GrunnYDesign: shared design tokens/components, actual MapKit route rendering, running and completion screens.
- MapWorkspaceView: previous map and API tools, reachable through the top-right map control; shares the same runtime models and signal bindings.
- Assets: exact Figma plus/minus/arrow/pace-flow SVG exports; named brand colors from Figma variables. System iOS font is used; Noto Sans KR is not bundled.

The five screen layouts use the white/mint/teal palette, rounded cards, large metrics and gradient CTA. They adapt using native stacks/scrolling and respect system safe areas. Device mockup/status-bar decorations are not app content. The design is light-only.

Intentional functional differences:
- Map and route are live MapKit content, not the Figma example drawing.
- Route copy explicitly states signal wait and slope are not yet included.
- Distance, elapsed time and pace use actual location records; no sample running results are injected.
- The decorative wave on Running is a Figma asset, not data. Completion's pace chart uses recorded GPS speeds and shows an empty state when insufficient.
- Voice/turn guidance is not implemented: the guide card opens the actual route map.
- Pause/lock controls are visibly marked pending and noninteractive; calorie value is unmeasured. Existing feature-development work remains paused.
- Sharing opens the native share sheet with actual distance/time text.

Validation: Simulator build succeeded. Visually inspected goal and loading screens; corrected native toolbar brand clipping and the tools-sheet → running presentation sequence. Existing authenticated iPhone 17 session was not reinstalled. iPhone 17 Pro was used for design verification. End-to-end route/run/completion and large accessibility text still require additional device/UI verification.
