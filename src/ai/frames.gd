class_name Frames
extends RefCounted
## Lets non-Node code wait for the next frame, so network and process polling never blocks the game.


static func next() -> Signal:
	return (Engine.get_main_loop() as SceneTree).process_frame
