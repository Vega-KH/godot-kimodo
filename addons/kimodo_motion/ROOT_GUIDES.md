# Scene root-path and facing guides

The **Guides** tab in **AI Motion** records root waypoints at the native
AnimationPlayer's current frame. The separate Pose Library remains the place
for reusable bone poses. Guides belong to the active motion session.

**Move character with guide** adds visual pose positioning: the guide moves and
turns Hips while the character's scene node stays fixed. Combined records leave
gold authored-pose ghosts; generated-take previews remain cyan.

## Author a route

1. Open a saved character scene with one Skeleton3D and an AnimationPlayer.
   Select the same character asset and reviewed rig profile in the AI Motion
   session. Connect to the updated backend once to obtain its canonical root
   reference; saved guides can subsequently be edited offline.
2. Open the animation to use as an authoring timeline, pause playback and scrub
   to a frame. The selected time rounds to the nearest Kimodo frame at 30 fps;
   that frame must be within the session's generation duration. Rounding does
   not move the native playhead or resample manually edited bones. You can change native clips
   without selecting the character again.
3. Select the scene character, skeleton or AnimationPlayer, then press
   **Use selected scene character**. Press **Select root guide in scene** to
   select the temporary cyan guide. Enable **Move character with guide** to move
   and turn the character's Hips with Godot's native gizmos. Height, tilt and other
   bone articulation are preserved. Disable it to edit the route independently.
   **Use selected scene character** also selects the same skeleton/player in
   Pose Library, whose saved pose list shows only compatible poses.
4. Enable **Record facing (+Z arrow)** when that waypoint should also constrain
   facing. Rotate the arrow with the native rotation gizmo. Travel is recorded
   on the ground plane; guide height does not specify root height.
5. Apply a pose from Pose Library if desired. In character-edit mode the guide
   follows its resulting Hips position/facing, including partial pose application.
6. Press **Record waypoint and pose at current frame** to capture both together,
   or **Record waypoint at current frame** for a route-only record. Scrub to another
   frame and repeat. The viewport shows authored pose ghosts or waypoint arrows,
   frame labels and straight segments between them.
   These lines display authored intent, not the generated motion or extra sampled
   constraints. Selecting a saved waypoint restores the guide's position/facing.

Recording over an existing frame requires replacement confirmation. Changing
the clip, cursor, guide, queued data or captured bones during that review cancels
the operation. Review the displayed hand/foot transfer differences before Generate.
**Remove selected record** and recording/clearing guides support Godot Undo/Redo
and session autosave. Guide edits do not key or modify the authoring animation.
Moving the guide with native gizmos supports editor Undo, including Hips following
the restored transform. Recording captures a snapshot; use Pose Library's existing
Apply & Key action when you also want native animation keys.

## Authored ghosts and editing records

Gold ghosts show the actual recorded character channels, including fingers;
they do not show the converted SOMA pose or predict generated motion. Each is
static and has a matching frame label. **Show authored pose ghosts** hides/shows
them without changing constraints. Waypoint-only records have cyan arrows/labels.

Select a record in the list (or a selectable ghost in the viewport) to restore
its pose and guide **at the current native frame**. The playhead stays unchanged.
Record there to reuse it at another frame; scrub to its labelled frame first to
replace the original. This keeps the Animation panel and the frame being recorded
in agreement. Pose restoration supports Undo and never queues a record implicitly.

A combined record stores its pose and waypoint as one action; Undo/Redo restores
both together. Removing it also removes its linked pose. Replacing it with a
waypoint-only record removes that linked pose after review. Clearing guides
explains removal of linked poses; independent Pose Library constraints are kept.
Requeuing a pose independently in Pose Library breaks its old combined link, so
it is preserved as an independent constraint rather than removed with the waypoint.

## Combine with poses and generate

The combined record button is the main way to assemble pose and path constraints
in the motion dock. Separate Pose Library queuing remains available.
At a frame shared with a full-body pose, root position and any recorded facing
must agree. **Match guide to queued pose at current frame** places the guide at
that pose's root and facing; then record the waypoint. This also avoids slight
neutral-hip orientation differences. Alternatively move/remove the conflicting
waypoint or disable its facing. Conflicts are reported before submission.

Keep the character's scene node and Skeleton3D node at their original placement
throughout authoring. To place a full-body pose along the route:

1. Scrub to the desired time and apply the library pose.
2. With **Move character with guide** enabled, move/rotate the guide. Apply the
   library pose first: a complete pose may replace earlier root positioning.
3. Press **Record waypoint and pose at current frame**. No separate pose queue
   or matching action is needed; the stored waypoint uses the converted root.

Manual Hips editing and separate queue → match → record remain supported.

Moving the character or Skeleton3D node changes the fixed scene reference and
invalidates guides. That node motion is not part of the queued bone pose. Restore
the node's original transform to continue; keep the existing guide points.
For guide-only route frames, move the cyan guide itself.

Generate from **Generate** after reviewing the points and optional facing.
The backend must advertise `root_path` support. The request and take archive
retain both the submitted constraints and authored scene placement/profile.
Existing sessions without guides continue to work.

## Preview, save and reopen

Select a generated or History take in **Preview & Save**, then press
**Show selected take in scene** in Guides. A translucent cyan character previews
that take at its archived placement and follows the paused native timeline.
**Hide scene preview** removes it. Guides and this preview are temporary editor
helpers and are excluded from saved scenes.
Authored pose ghosts are also temporary and never become part of the scene file.

Session reopening and History reconstruction work offline. Open the original
scene and bind its character again. Saved pose references and authored channels
reconstruct the ghosts and support continued combined editing offline. Legacy
Goal 23 sessions without that reference still support their old route workflow;
connect once and bind to establish the new pose reference. Clearing/rebasing an
entire guide reference requires connecting again. Scene placement/profile must match the
archived guide reference. Save and Accept retain their existing explicit export
and production-library behavior; exported animation is in character space, with
scene placement separate.

## Placement and limits

Scene translation, yaw and positive uniform scale are supported. Tilt, reflection,
shear or nonuniform skeleton placement are rejected. Profile scale and scene scale
are each applied once. Moving the character or changing its profile invalidates
the guide reference. Restore the original reference or explicitly **Clear guides /
use changed placement**, select the character again and reauthor; automatic rebase
is not provided. Shortening duration past a waypoint is rejected at submission.

Kimodo's generated route is approximate. This tool does not provide terrain,
collision avoidance, arbitrary height control, hand/foot targets or positional
fitting of character poses. Pose orientation transfer can still move end effectors
on characters with different proportions; see the development goals for that
separate limitation.
