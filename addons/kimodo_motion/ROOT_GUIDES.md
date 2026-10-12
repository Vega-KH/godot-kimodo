# Scene root-path and facing guides

The **Guides** tab in **AI Motion** records root waypoints at the native
AnimationPlayer's current frame. The separate Pose Library remains the place
for reusable bone poses. Guides belong to the active motion session.

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
   select the temporary cyan guide. Move it with Godot's native position gizmo.
4. Enable **Record facing (+Z arrow)** when that waypoint should also constrain
   facing. Rotate the arrow with the native rotation gizmo. Travel is recorded
   on the ground plane; guide height does not specify root height.
5. Press **Record waypoint at current frame**, scrub to another frame and repeat.
   The viewport shows waypoint frame labels and straight segments between them.
   These lines display authored intent, not the generated motion or extra sampled
   constraints. Selecting a saved waypoint restores the guide's position/facing.

Recording over an existing frame requires replacement confirmation. Changing
the clip, cursor or destination during that review cancels the operation.
**Remove selected waypoint** and recording/clearing guides support Godot Undo/Redo
and session autosave. Guide edits do not key or modify the authoring animation.

## Combine with poses and generate

Queue complete body poses using Pose Library, then author the route in Guides.
At a frame shared with a full-body pose, root position and any recorded facing
must agree. **Match guide to queued pose at current frame** places the guide at
that pose's root and facing; then record the waypoint. This also avoids slight
neutral-hip orientation differences. Alternatively move/remove the conflicting
waypoint or disable its facing. Conflicts are reported before submission.

Keep the character's scene node and Skeleton3D node at their original placement
throughout authoring. To place a second full-body pose elsewhere along the route:

1. Scrub to the desired time and apply the library pose.
2. Move/rotate the **Hips bone** to author that pose's root travel and turning.
   Apply the library pose first: a complete pose may overwrite earlier Hips edits.
   Preserve these edits with native bone keys if you want them to survive scrubbing.
3. Queue the current complete frame in Pose Library and confirm.
4. Match the guide to that queued pose, then record the waypoint at the same time.

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

Session reopening and History reconstruction work offline. Open the original
scene and bind its character again. Scene placement and profile must match the
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
