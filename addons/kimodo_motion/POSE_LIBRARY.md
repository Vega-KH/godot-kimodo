# Pose Library

Pose Library is a separate editor dock in Kimodo Motion Studio. Capture, edit,
save and apply work without an AI Motion session or a backend connection.
The Constraints tab connects the authored character frame to the active AI
Motion session. Goal 22 was owner-accepted on 2026-10-11.

## Choose a character and frame

Selecting **Use selected scene character** in AI Motion also selects that
character in Pose Library. The saved pose list automatically filters to the
selected skeleton's compatible hierarchy/rest pose and refreshes on character
changes. With no character selected the list is empty. Pose files are kept;
select their compatible character to see them again.

Open a scene containing your character and an AnimationPlayer. Select the
character, its skeleton or its player in the Scene tree, then click **Use selected
character**. The selected subtree must resolve to one Skeleton3D and one
AnimationPlayer; select a smaller subtree if several players are present.
Turn off Skeleton3D's **Show Rest Only**.

Open that AnimationPlayer in Godot's native **Animation** panel. Choose a clip
and scrub to the desired frame there. Pose Library follows the player's selected
animation and cursor automatically; newly created clips appear without clicking
**Use selected character** again. Its animation selector and frame display are
read-only. Frame numbers use the animation's step; keys use the exact time without
rounding to a separate FPS setting. Pause playback before capturing or keying.
Use normal scrubbing that evaluates the character; timeline-only cursor moves
do not update the player's evaluated frame.

This workflow supports active AnimationPlayers edited in the native panel.
Direct Animation resource editing and AnimationTree/inactive-player preview use
a separate editor player and are outside this workflow. Select the character's
AnimationPlayer instead. Godot controls frame evaluation; **Capture current
frame** reads the displayed bone values, including manual edits, without seeking
or resampling the source clip.

## Capture, save and edit

1. In **Capture**, choose bones with Ctrl/Shift, or **Select all bones**.
   Choose Position, Rotation and/or Scale. Rotation is the default; skeleton
   root bones are excluded unless **Include skeleton root channels** is checked.
2. Edit the displayed bones using Godot's skeleton/animation tools. Enter a pose
   name and click **Capture current frame**. This captures their current values
   without modifying the source clip.
3. Click **Save pose as…** and choose a new `.tres` file. Existing files are
   refused. The default library folder is `res://animations/kimodo/poses`.
   **Refresh saved poses** lists valid poses there; **Open pose…** opens a pose
   elsewhere in the project.
4. Open and apply a saved pose, then edit the Skeleton3D through Godot.
5. **Capture edits to opened pose channels** keeps that pose's channel mask and
   creates a new pose identity. **Save pose as…** saves the revised pose to a new
   file. To change the mask, use the normal current-pose capture instead.

A pose resource contains rig metadata and a native Animation with one sample
at time zero per included bone channel. It contains no model or live node.
Missing channels mean leave those values unchanged. A finger-only pose can be
applied repeatedly over body animation without replacing the body's keys.
Poses require the same bone names, parent hierarchy and rest transforms.
Equivalent bone reindexing is supported; cross-rig library retargeting is not.

## Apply and key

**Preview pose** temporarily sets the included channels. **Cancel preview**
restores their previous values and resumes previously playing animation.
**Apply pose** commits only those channels, with Undo/Redo.

**Apply & Key at current frame** sets and keys the included channels in the
animation and frame currently selected in Godot's Animation panel. It preserves
other channels, times, tracks and settings.
If keys already exist at that time, a confirmation lists their count; Cancel
leaves the animation unchanged. A changed destination invalidates a pending
confirmation, including changing the selected clip or moving its cursor.
Undo/Redo restores the animation and edited pose values. Moving the native cursor
during a temporary preview ends that preview without restoring an old frame over
the newly evaluated character.

Imported animations can be captured, but must be copied before keying.
Enter a new animation name and click **Copy selected animation for editing**.
The independent copy appears under `pose_edits/<name>`; select it in Godot's
Animation panel. Save the scene to persist the copy and its keys. Godot's normal
animation resource saving remains available for external editable libraries.

## Queue full-body Kimodo constraints

Choose the matching character/profile in AI Motion, open a session and connect
to the backend. Seek the destination animation frame, apply partial poses and
make any manual edits before queuing it.

In **Constraints**, scrub to the desired native time and click **Queue
current frame…**. The destination rounds to the nearest 30 FPS Kimodo frame,
without moving the playhead or resampling bone edits. This captures the complete character state, including
channels that were absent from a partial library pose. Review the conversion
report and confirm. A constraint at the same frame is replaced. Queue more
frames explicitly; the add-on does not infer constraints from every native key.
Generate using AI Motion when ready. Removing/queuing frames is undoable and
autosaved. Recapture a queued constraint after further character edits, or
after changing its rig profile. Editing constraints is locked during generation.

The converter reconstructs SOMA global orientations through the profile's rest
and palm frames, then decomposes them into SOMA-30 local xyzw quaternions.
Collapsed/absent joints inherit the preceding reconstructed orientation;
unobservable articulation has a deterministic identity local rotation. Root
travel/height follows the profile's translation scale. Skeleton-relative
coordinates exclude the scene node's placement.
When combining with [root guides](ROOT_GUIDES.md), keep the character's scene
node fixed. In Guides, enable **Move character with guide**, apply a library pose,
move/rotate the guide, then **Record waypoint and pose at current frame**.
The guide follows applied Hips changes. Separate bone edits/queuing and guide
matching remain available. Moving the scene node does not add travel
or turning to the queued pose and invalidates the guide reference.

The backend's full-body conditioning constrains FK joint positions, root
height/path and heading. It does not promise exact reproduction of every twist.
Fine finger/detail bones remain in your pose and native animation; the report
lists the bones excluded from conditioning. Apply those detail poses to the
generated native animation where desired.

Current conversion preserves orientations; it has no positional-fitting solver.
Different limb proportions can change hand/foot placement. The confirmation
reports motion-position differences in meters after accounting for root scale
and the transferred neutral baseline; these are not bounds on generation error.
Non-root translation and body/ancestor scaling edits remain saved locally but
are rejected for conversion with an explanation. IK/control-driven rigs are
outside this implementation. The user deferred positional fitting for next-goal
discussion; the displayed orientation-transfer limits remain in this version.

Generation archives retain both the exact authored character channels/profile
configuration and the actual converted request. Saved library poses and artist
animation copies are independent of sessions. Session deletion does not remove
them. Back up poses and authored scenes/libraries alongside your other assets.
