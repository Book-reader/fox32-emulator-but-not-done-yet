module gui;
import emulator;
import common;
import logger;

import std::io;
import std::thread;
import raylib5::rl;

char[common::BG_FB_SIZE] empty_overlay;
struct MousePos
{
	Mutex mutex;
	SplitInt pos;
}

fn SplitInt MousePos.get(&self)
{
	self.mutex.lock()!!;
	defer (void)self.mutex.unlock();
	return self.pos;
}

fn void MousePos.set(&self, uint x, uint y)
{
	self.mutex.lock()!!;
	defer (void)self.mutex.unlock();
	self.pos = {x, y};
}

MousePos mouse_pos;

fn int run_gui(void* _arg) => @pool_init(mem, 4096, allocator::temp_allocator_buffer_size)
{
	mouse_pos.mutex.init()!!;
	defer (void)mouse_pos.mutex.destroy();

	ThreadData* arg = (ThreadData*)_arg;
	Cpu* cpu = arg.cpu;
	bool* running = arg.running;
	rl::initWindow(...common::DISP_SIZE, "fox33");
	rl::setTargetFPS(60);

	// io::printn(*cpu);
	// TODO: thread safety stuff & vblank using interrupt
	Image img = {
		.data = cpu.mem_get(common::BG_FB, common::BG_FB_SIZE)!!,//ram[0x02000000..],//.fb.data,
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

	while (*running && !rl::windowShouldClose())
	{
		rl::beginDrawing();
		{
			Vector2 pos = rl::getMousePosition();
			mouse_pos.set((uint)pos.x.clamp(0, 640), (uint)pos.y.clamp(0, 480));
			// logger::debug("set mouse pos to <%s, %s>", mouse_pos.get().first, mouse_pos.get().second);
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
		rl::endDrawing();
		*arg.vsync_int = true;
		// signal that it's done. needs to be done after the drawing ends to be able to tell the main loop if it has exited
		// defer emulator::gui_done.push(!rl::windowShouldClose())!!;
	}
	rl::unloadTexture(bg_fb);
	foreach (overlay : overlays) rl::unloadTexture(overlay);
	rl::unloadShader(boolean_transparency);
	rl::closeWindow();
	logger::error("Gui closed, exiting");
	*running = false;
	return 0;
}
