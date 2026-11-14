# macOS 26 design reference

User-supplied reference, checked 2026-11-14:
[Apple macOS 26 UI kit on Figma Community](https://www.figma.com/community/file/1543337041090580818/macos-26).
The public page identifies Apple as the author and says it was updated July 24, 2026.
It lists controls, windows/alerts/popovers/sheets, desktop templates including
notifications/menu bar/dock, system colours, materials, typography and vibrancy.

## Access verified

The official Figma MCP connection is authenticated in T3 Code's active
ChatGPT – Personal provider. On 2026-11-14 it successfully read the user's
[inspectable design file](https://www.figma.com/design/aX0hMTnr1udLY1Vtyhdva0/macOS-26--Community-?node-id=121-18094).
PDF/SVG export is no longer required for this file.

The supplied node `121:18094` is the **Examples page**, rather than a component.
Its metadata lists notification, form, list, menu, alert, dialog and window
examples. Design context and screenshots were retrieved for the concrete
notification and form examples below; the form's variables were also read.

## Verified measurements

Values below come from inspectable layers and variables, not preview pixels.
They describe the inspected examples and their resolved variants; they are not
universal values for every macOS control size or state. Shared control geometry
is now applied through `common/geometry.plm`; the
current Beskar contract and intentional adaptations are in [UI_STANDARDS.md](UI_STANDARDS.md).

### Notifications

Source: [Examples/Notifications, node 2548:2860](https://www.figma.com/design/aX0hMTnr1udLY1Vtyhdva0/macOS-26--Community-?node-id=2548-2860).

| Property | Verified value |
| :--- | :--- |
| Card width in this desktop example | 382 |
| Referenced Notification component's default width | 344; overridden by the example's container |
| Card corner radius | 16 |
| Padding | 13 left, 9 right, 12 top and bottom |
| App icon | 32 × 32 |
| Gap between icon and text | 13 |
| Title/body type | 13 size, 16 line height; bold title, regular body |
| Timestamp type | 11 size, 14 line height |
| Gap between notification cards | 16 |
| Example placement | 16 from right edge, 49 from top edge |
| Card shadow | x 0, y 8, blur 40, spread 0, black at 12% |

The shadow above is an intentional design effect while the card is visible.
Retained notification/calendar pixels after closure are a separate rendering
problem documented in [RENDERING_NOTES.md](RENDERING_NOTES.md).

### Form controls

Source: [Examples/Form, node 2548:2849](https://www.figma.com/design/aX0hMTnr1udLY1Vtyhdva0/macOS-26--Community-?node-id=2548-2849).
Button geometry is resolved from `Global/Height`, `Button/Padding - Horizontal`
and `Button/Radius` in this example.

| Property | Verified value |
| :--- | :--- |
| Push button height / horizontal padding / radius | 24 / 16 / 6 |
| Global control font size | 13 |
| Body type | SF Pro Regular, 13 size, 16 line height |
| Form row minimum height | 42 |
| Checkbox | 16 × 16, radius 5.5 |
| Radio button / selected dot | 16 / 4.8 diameter |
| Switch track | 36 × 16 |
| Switch knob width / inset | 21 / 1.5 |
| Field left / right inset | 8 / 4 |

The inspected examples resolve light appearance colours. Dark appearance and
other control variants still need inspection before adopting a complete style.
Figma's Liquid Glass variables are also available, but their numeric settings
are specific to Figma's renderer and must not be copied into pleamar as if they
were equivalent shader parameters.

### Additional size variants

The following dimensions were read from the component-page metadata during the
consistency planning pass. They establish available sizes; detailed appearance
and state inspection is still required before implementation.

| Source page | Measured example dimensions |
| :--- | :--- |
| [Buttons, 207:14487](https://www.figma.com/design/aX0hMTnr1udLY1Vtyhdva0/macOS-26--Community-?node-id=207-14487) | Arrow-button examples: 16, 20, 24, 28 and 36 square |
| [Toggles, 207:14470](https://www.figma.com/design/aX0hMTnr1udLY1Vtyhdva0/macOS-26--Community-?node-id=207-14470) | Switch examples: 36×16, 44×20, 54×24, 64×28 and 80×36 |
| [Search Fields, 207:14491](https://www.figma.com/design/aX0hMTnr1udLY1Vtyhdva0/macOS-26--Community-?node-id=207-14491) | Example heights: 16, 20, 24, 28 and 36; widths 120 |

## Applying the reference

The shell-wide migration record is in
[SHELL_CONSISTENCY_PLAN.md](SHELL_CONSISTENCY_PLAN.md). Its target values distinguish
measured kit values from Beskar choices and stage the work by shared controls and
their callers.

Record verified source frames and their values before changing theme tokens or
shared controls. Start with buttons/icon buttons, row height and spacing,
notification cards, calendar density and panel corners. Check both light/dark
appearances, disabled/selected states and the fonts available on this desktop.

Apply approved values in the existing theme and shared rendering libraries.
Component geometry does not require another surface, data owner, timer or process.
Keep the existing monitor routing and island/panel ownership.
