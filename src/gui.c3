module gui;
import emulator;
import common;
import logger;
import atom;

import std::io;
import std::thread;
import raylib5::rl;

char[common::BG_FB_SIZE] empty_overlay;

bitstruct MouseState : uint @littleendian
{
	bool pressed : 0;
	bool released : 1;
	bool held : 2;
}

Atom {SplitInt} mouse_pos;
Atom {MouseState} mouse_state;

fn int run_gui(void* _arg) => @pool_init(mem, 4096, allocator::temp_allocator_buffer_size)
{
	mouse_pos.init()!!;
	defer (void)mouse_pos.destroy();
	mouse_state.init()!!;
	defer (void)mouse_state.destroy();

	ThreadData* arg = (ThreadData*)_arg;
	Cpu* cpu = arg.cpu;
	bool* running = arg.running;
	rl::initWindow(...common::DISP_SIZE, "fox33");
	rl::setTargetFPS(60);
	// TODO: this dosn't work on wayland nixos because raylib built with glfw-wayland depends on a libwayland-client which isn't in the library path on nixos & glfw-x11 can't hide the cursor, might switch to sdl2 instead
	rl::hideCursor();

	// io::printn(*cpu);
	// TODO: thread safety stuff & vblank using interrupt
	Image img = {
		.data = cpu.mem_get(common::BG_FB, common::BG_FB_SIZE)!!,
		.width = common::DISP_SIZE.x,
		.height = common::DISP_SIZE.y,
		.format = UNCOMPRESSED_R8G8B8A8,
		.mipmaps = 1,
	};

	Texture2D bg_fb = rl::loadTextureFromImage(img);

	Texture2D[common::NUM_OVERLAYS] overlays;
	foreach (&overlay : overlays)
	{
		*overlay = rl::loadTextureFromImage({
			.data = &empty_overlay,
			.width = common::DISP_SIZE.x,
			.height = common::DISP_SIZE.y,
			.format = UNCOMPRESSED_R8G8B8A8,
			.mipmaps = 1,
		});
	}

	Shader boolean_transparency = rl::loadShaderFromMemory(
		vs: null,
		fs:
// "borrowed" from https://github.com/raysan5/raylib/blob/b9c2ecc447a1aaed562f23932125c0c41e59e7f1/examples/shaders/resources/shaders/glsl330/grayscale.fs
// and slightly modified
`
#version 330
in vec2 fragTexCoord;
in vec4 fragColor;

uniform sampler2D texture0;
uniform vec4 colDiffuse;

out vec4 finalColor;

void main()
{
	vec4 texelColor = texture(texture0, fragTexCoord)*colDiffuse*fragColor;

	finalColor = vec4(texelColor.r, texelColor.g, texelColor.b, texelColor.a == 0 ? 0.0 : 1.0);
}`);

	arg.gui_init.push(true)!!;

	while (@atomic_load(*running) && !rl::windowShouldClose())
	{
		rl::beginDrawing();
		{
			// logger::info("Mouse state at start of frame: %.32b", (uint)mouse_state.get()!!);
			Vector2 pos = rl::getMousePosition();
			(void)mouse_pos.set({(uint)pos.x.clamp(0, 640), (uint)pos.y.clamp(0, 480)});
			// logger::debug("set mouse pos to <%s, %s>", mouse_pos.get().first, mouse_pos.get().second);
			if (rl::isMouseButtonPressed(LEFT))
			{
				// logger::info("Mouse pressed/held");
				(void)mouse_state.@use(; #val)
				{
					#val.pressed = true;
					#val.held = true;
				};
			}
			else if (rl::isMouseButtonReleased(LEFT))
			{
				// logger::info("Mouse released");
				(void)mouse_state.@use(; #val)
				{
					#val.held = false;
					#val.released = true;
				};
			}
		}
		rl::clearBackground(rl::BLACK);
		rl::updateTexture(bg_fb, cpu.mem_get(common::BG_FB, common::BG_FB_SIZE)!!);
		rl::drawTexture(bg_fb, 0, 0, rl::WHITE);

		foreach (i, overlay_tex : overlays)
		{
			DisplayOverlay* overlay = &cpu.overlays[i];
			if (overlay.enable)
			{
				rl::updateTextureRec(overlay_tex, {0, 0, ...overlay.size}, cpu.mem_get(overlay.fb_ptr, overlay.size.x * overlay.size.y * 4)!!);

				rl::beginShaderMode(boolean_transparency);
				rl::drawTextureRec(overlay_tex, {0, 0, ...overlay.size}, {...overlay.pos}, rl::WHITE);
				rl::endShaderMode();
			}
		}

		rl::drawFPS(10, 10);

		// moving this after the endDrawing call fixes it *most* of the time, still happens sometimes tho
		// io::eprintn("vsync");
		// logger::info("Mouse state at end of frame: %.32b", (uint)mouse_state.get()!!);
		@atomic_store(*arg.vsync_int, true);
		rl::endDrawing();

	//	io::printn("vsync");
		// signal that it's done. needs to be done after the drawing ends to be able to tell the main loop if it has exited
		// defer emulator::gui_done.push(!rl::windowShouldClose())!!;
	}
	rl::unloadTexture(bg_fb);
	foreach (overlay : overlays) rl::unloadTexture(overlay);
	rl::unloadShader(boolean_transparency);
	rl::closeWindow();
	logger::error("Gui closed, exiting");
	@atomic_store(*running, false);
	return 0;
}

module atom {Type};
import std::thread;

struct Atom
{
	Mutex mutex;
	Type val;
}

fn Type? Atom.get(&self)
{
	self.mutex.lock()!;
	defer (void)self.mutex.unlock();
	return self.val;
}

fn void? Atom.set(&self, Type val)
{
	self.mutex.lock()!;
	defer (void)self.mutex.unlock();
	self.val = val;
}

fn void? Atom.init(&self, Type val = {})
{
	self.mutex.init()!;
	self.val = val;
}

fn void? Atom.destroy(&self)
{
	self.mutex.destroy()!;
}

macro void? Atom.@use(&self; @body(#val))
{
	self.mutex.lock()!;
	defer (void)self.mutex.unlock();
	@body(self.val);
}
