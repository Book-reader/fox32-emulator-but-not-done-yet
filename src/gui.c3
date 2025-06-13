module gui;
import emulator;
import common;
import logger;
import atom;

import std::io;
import std::thread;
import std::collections::linkedlist;
import std::collections::tuple;
import raylib5::rl;

typedef ScanCode = inline char;

// 512 is semi-arbitrary, but should work fine with how raylib does keycodes
const ScanCode[512] SCANCODES = {
//	[(int)rl::KEY_NULL] = 0x0B,
	[(int)rl::KEY_APOSTROPHE] = 0x28,
	[(int)rl::KEY_COMMA] = 0x33,
	[(int)rl::KEY_MINUS] = 0x0C,
	[(int)rl::KEY_PERIOD] = 0x34,
	[(int)rl::KEY_SLASH] = 0x35,
	[(int)rl::KEY_ZERO] = 0x0B,
	[(int)rl::KEY_ONE] = 0x02,
	[(int)rl::KEY_TWO] = 0x03,
	[(int)rl::KEY_THREE] = 0x04,
	[(int)rl::KEY_FOUR] = 0x05,
	[(int)rl::KEY_FIVE] = 0x06,
	[(int)rl::KEY_SIX] = 0x07,
	[(int)rl::KEY_SEVEN] = 0x08,
	[(int)rl::KEY_EIGHT] = 0x09,
	[(int)rl::KEY_NINE] = 0x0A,
	[(int)rl::KEY_SEMICOLON] = 0x27,
	[(int)rl::KEY_EQUAL] = 0x0D,
	[(int)rl::KEY_A] = 0x1E,
	[(int)rl::KEY_B] = 0x30,
	[(int)rl::KEY_C] = 0x2E,
	[(int)rl::KEY_D] = 0x20,
	[(int)rl::KEY_E] = 0x12,
	[(int)rl::KEY_F] = 0x21,
	[(int)rl::KEY_G] = 0x22,
	[(int)rl::KEY_H] = 0x23,
	[(int)rl::KEY_I] = 0x17,
	[(int)rl::KEY_J] = 0x24,
	[(int)rl::KEY_K] = 0x25,
	[(int)rl::KEY_L] = 0x26,
	[(int)rl::KEY_M] = 0x32,
	[(int)rl::KEY_N] = 0x31,
	[(int)rl::KEY_O] = 0x18,
	[(int)rl::KEY_P] = 0x19,
	[(int)rl::KEY_Q] = 0x10,
	[(int)rl::KEY_R] = 0x13,
	[(int)rl::KEY_S] = 0x1F,
	[(int)rl::KEY_T] = 0x14,
	[(int)rl::KEY_U] = 0x16,
	[(int)rl::KEY_V] = 0x2F,
	[(int)rl::KEY_W] = 0x11,
	[(int)rl::KEY_X] = 0x2D,
	[(int)rl::KEY_Y] = 0x15,
	[(int)rl::KEY_Z] = 0x2C,
	[(int)rl::KEY_LEFT_BRACKET] = 0x1A,
	[(int)rl::KEY_BACKSLASH] = 0x2B,
	[(int)rl::KEY_RIGHT_BRACKET] = 0x1B,
	[(int)rl::KEY_GRAVE] = 0x29,
	[(int)rl::KEY_SPACE] = 0x39,
	[(int)rl::KEY_ESCAPE] = 0x01,
	[(int)rl::KEY_ENTER] = 0x1C,
	[(int)rl::KEY_TAB] = 0x0F,
	[(int)rl::KEY_BACKSPACE] = 0x0E,
	// [(int)rl::KEY_INSERT] = 0x,
	// [(int)rl::KEY_DELETE] = 0x,
	[(int)rl::KEY_RIGHT] = 0x6A,
	[(int)rl::KEY_LEFT] = 0x69,
	[(int)rl::KEY_DOWN] = 0x6C,
	[(int)rl::KEY_UP] = 0x67,
	// [(int)rl::KEY_PAGE_UP] = 0x,
	// [(int)rl::KEY_PAGE_DOWN] = 0x,
	// [(int)rl::KEY_HOME] = 0x,
	// [(int)rl::KEY_END] = 0x,
	[(int)rl::KEY_CAPS_LOCK] = 0x3A,
	// [(int)rl::KEY_SCROLL_LOCK] = 0x,
	// [(int)rl::KEY_NUM_LOCK] = 0x,
	// [(int)rl::KEY_PRINT_SCREEN] = 0x,
	// [(int)rl::KEY_PAUSE] = 0x,
	[(int)rl::KEY_F1] = 0x3B,
	[(int)rl::KEY_F2] = 0x3C,
	[(int)rl::KEY_F3] = 0x3D,
	[(int)rl::KEY_F4] = 0x3E,
	[(int)rl::KEY_F5] = 0x3F,
	[(int)rl::KEY_F6] = 0x40,
	[(int)rl::KEY_F7] = 0x41,
	[(int)rl::KEY_F8] = 0x42,
	[(int)rl::KEY_F9] = 0x43,
	[(int)rl::KEY_F10] = 0x44,
	[(int)rl::KEY_F11] = 0x57,
	[(int)rl::KEY_F12] = 0x58,
	[(int)rl::KEY_LEFT_SHIFT] = 0x2A,
	[(int)rl::KEY_LEFT_CONTROL] = 0x1D,
	[(int)rl::KEY_LEFT_ALT] = 0x38,
	// [(int)rl::KEY_LEFT_SUPER] = 0x,
	[(int)rl::KEY_RIGHT_SHIFT] = 0x36,
	// [(int)rl::KEY_RIGHT_CONTROL] = 0x,
	// [(int)rl::KEY_RIGHT_ALT] = 0x,
	// [(int)rl::KEY_RIGHT_SUPER] = 0x,
	// [(int)rl::KEY_KB_MENU] = 0x,
	[(int)rl::KEY_KP_0] = 0x0B,
	[(int)rl::KEY_KP_1] = 0x02,
	[(int)rl::KEY_KP_2] = 0x03,
	[(int)rl::KEY_KP_3] = 0x04,
	[(int)rl::KEY_KP_4] = 0x05,
	[(int)rl::KEY_KP_5] = 0x06,
	[(int)rl::KEY_KP_6] = 0x07,
	[(int)rl::KEY_KP_7] = 0x08,
	[(int)rl::KEY_KP_8] = 0x09,
	[(int)rl::KEY_KP_9] = 0x0A,
	// [(int)rl::KEY_KP_DECIMAL] = 0x,
	// [(int)rl::KEY_KP_DIVIDE] = 0x,
	// [(int)rl::KEY_KP_MULTIPLY] = 0x,
	// [(int)rl::KEY_KP_SUBTRACT] = 0x,
	// [(int)rl::KEY_KP_ADD] = 0x,
	[(int)rl::KEY_KP_ENTER] = 0x1C,
	// [(int)rl::KEY_KP_EQUAL] = 0x,
};
Tuple{bool, ScanCode}[512] held_keys;

char[common::BG_FB_SIZE] empty_overlay;

bitstruct MouseState : uint @littleendian
{
	bool pressed : 0;
	bool released : 1;
	bool held : 2;
}

bitstruct KeyEvent : uint @littleendian
{
	ScanCode code : 0..6;
	bool released : 7;
}
const KeyEvent NONE = {};

Atom {SplitInt} mouse_pos;
Atom {MouseState} mouse_state;

Atom {LinkedList {KeyEvent}} key_queue @private;


<*
	// @ensure return != 0 ? io::printfn("returned key %s (r: %s, c: %s)", return, ((KeyEvent)return).released, ((KeyEvent)return).code)!! != 0 : true
*>
fn uint get_key() @inline => (uint)key_queue.call("pop_front") ?? (uint)NONE;

fn int run_gui(void* _arg) => @pool_init(mem, 4096, allocator::temp_allocator_buffer_size)
{
	mouse_pos.init()!!;
	defer (void)mouse_pos.destroy();
	mouse_state.init()!!;
	defer (void)mouse_state.destroy();
	key_queue.init()!!;
	key_queue.call("init", mem)!!;
	defer
	{
		key_queue.call("free")!!;
		(void)key_queue.destroy();
	}
	foreach (i, &key : held_keys)
	{
		key.second = SCANCODES[i];
	}

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
			while (int c = rl::getKeyPressed())
			{
				if (held_keys[c].second != 0)
				{
					held_keys[c].first = true;
					(void)key_queue.call("push", {held_keys[c].second, false});
					// io::printfn("got key press: %c, scancode: 0x%.2x", c, SCANCODES[c]);
				}
				
			}
			foreach (i, &key : held_keys)
			{
				if (key.first) if (rl::isKeyReleased((KeyboardKey)i))
				{
					key.first = false;
					(void)key_queue.call("push", {key.second, true});
					// io::printfn("got key release: 0x%.2x", key.second);
				}
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
				if (try rl::updateTextureRec(overlay_tex, {0, 0, ...overlay.size}, cpu.mem_get(overlay.fb_ptr, overlay.size.x * overlay.size.y * 4)))
				{
					// io::printfn("overlay pos: %s, normalised: %s", overlay.pos, offset);
					rl::beginShaderMode(boolean_transparency);
					rl::drawTextureRec(overlay_tex, {0, 0, ...overlay.size}, {...overlay.pos}, rl::WHITE);
					rl::endShaderMode();
				}
				else
				{
					logger::warn("[GUI] page fault while getting address of overlay %s at ptr 0x%.8x, size %s, byte size: %s", i, overlay.fb_ptr, overlay.size, overlay.size.x * overlay.size.y * 4);
				}
			}
		}

		rl::drawFPS(10, 10);

		// moving this after the endDrawing call fixes it *most* of the time, still happens sometimes tho
		// io::eprintn("vsync");
		// logger::info("Mouse state at end of frame: %.32b", (uint)mouse_state.get()!!);

		// if for some reason the cpu can't complete a single vsync interrupt per frame, wait a little
		while (@unlikely(@atomic_load(*arg.vsync_int))) thread::sleep_ms(1);
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

macro Atom.call(&self, String $method, ...)
{
	self.mutex.lock()!;
	defer (void)self.mutex.unlock();
	return self.val.$eval($method)($vasplat);
}
