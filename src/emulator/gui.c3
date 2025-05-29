module gui;
import emulator;
import logger;

import std::io;
import raylib5::rl;


fn int run_gui(void* arg) => @pool_init(mem, 4096, allocator::temp_allocator_buffer_size)
{
	Cpu* cpu = ((ThreadData*)arg).cpu;
	bool* running = ((ThreadData*)arg).running;
	rl::initWindow(640, 480, "fox33");
	rl::setTargetFPS(60);
	defer rl::closeWindow();

	// io::printn(*cpu);
	// TODO: thread safety stuff & vblank using interrupt
	Image img = {
		.data = cpu.mem_get(0x02000000, 640*480*4),//ram[0x02000000..],//.fb.data,
		.width = 640,
		.height = 480,
		.format = UNCOMPRESSED_R8G8B8A8,
		.mipmaps = 1
	};

	Texture2D tex = rl::loadTextureFromImage(img);

	((ThreadData*)arg).gui_init.push(true)!!;

	while (*running && !rl::windowShouldClose())
	{
		rl::beginDrawing();

		rl::updateTexture(tex, cpu.mem_get(0x02000000, 640*480*4));

		// emulator::gui_upd.pop()!!;
		// logger::warn("Not implemented yet");
		rl::drawTexture(tex, 0, 0, rl::WHITE);
		
		rl::drawFPS(10, 10);
		rl::endDrawing();
		// signal that it's done. needs to be done after the drawing ends to be able to tell the main loop if it has exited
		// defer emulator::gui_done.push(!rl::windowShouldClose())!!;
	}
	*running = false;
	logger::error("Gui closed, exiting");
	return 0;
}
