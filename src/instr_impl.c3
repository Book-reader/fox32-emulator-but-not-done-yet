module emulator;
import common;
import logger;
import gui;
import disk;

import std::io;
import std::math;
import std::time::datetime;
import libc;

attrdef @Inst = @inline, @maydiscard;

// NOTE: #src and #dst are FUNCTIONS that will be called EVERY TIME they are used
// this is fine when debug printing is enabled, but not otherwise
fn void? Cpu.inst_brk(&self, Instruction inst) @Inst => self.@setup(inst, W32; #src, #dst)
{
	// self.move_forward(W32, inst::BRK, inst);
	self.throw(EXC_BREAK);
}

fn void? Cpu.inst_mcl(&self, Instruction inst) @Inst => self.@setup(inst, W32; #src, #dst)
{
	self.mmu_enabled = false;
}

fn void? Cpu.inst_mse(&self, Instruction inst) @Inst => self.@setup(inst, W32; #src, #dst)
{
	self.mmu_enabled = true;
}

fn void? Cpu.inst_ise(&self, Instruction inst) @Inst => self.@setup(inst, W32; #src, #dst)
{
	self.flags.interrupt = true;
	self.handle_deferred_interrupts();
}

fn void? Cpu.inst_icl(&self, Instruction inst) @Inst => self.@setup(inst, W32; #src, #dst)
{
	self.flags.interrupt = false;
}

fn void? Cpu.inst_inc(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("Incrementing %s", #src);
	$Type res @noinit;

	self.flags.carry = math::overflow_add(#src, ($Type)(1 << inst.dst.ordinal), &res);
	self.flags.zero = res == 0;

	self.set_val($width, inst, SRC, res)!;
}

fn void? Cpu.inst_dec(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("Decrementing %s", #src);
	$Type res @noinit;
	$Type src = #src;
	bool over = math::overflow_sub(src, ($Type)(1 << inst.dst.ordinal), &res);
	self.set_val($width, inst, SRC, res)!;
	self.flags.carry = over;
	self.flags.zero = res == 0;
	// logger::info("Decrementing %s by %s (%s) = %s; carry: %s, zero: %s", src, (1 << inst.dst.ordinal), inst.dst, res, self.flags.carry, self.flags.zero);
}

fn void? Cpu.inst_add(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("Adding %s and %s", #dst, #src);
	$Type res @noinit;
	// This also sets res
	self.flags.carry = math::overflow_add(#dst, #src, &res);
	self.flags.zero = res == 0;
	self.set_val($width, inst, DST, res)!;

	// if (res == 0x04000000) self.error("Encountered 0x04000000 (bad)");
}

fn void? Cpu.inst_sub(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("Subtracting %s and %s", #dst, #src);
	$Type res @noinit;
	// This also sets res
	self.flags.carry = math::overflow_sub(#dst, #src, &res);
	self.flags.zero = res == 0;
	self.set_val($width, inst, DST, res)!;
}

fn void? Cpu.inst_mul(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("multiplying %s and %s", #dst, #src);
	$Type res @noinit;
	// This also sets res
	self.flags.carry = math::overflow_mul(#dst, #src, &res);
	self.flags.zero = res == 0;
	self.set_val($width, inst, DST, res)!;
}

fn void? Cpu.inst_imul(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	var $IType = $width.itype;
	logger::debug("multiplying %s and %s", ($IType)#dst, ($IType)#src);
	$IType res @noinit;
	// This also sets res
	self.flags.carry = math::overflow_mul(($IType)#dst, ($IType)#src, &res);
	self.flags.zero = res == 0;
	self.set_val($width, inst, DST, ($Type)res)!;
}


// TODO: merge div, idiv, rem, irem, etc with a macro/generic that just replaces the operand and type (signed vs unsigned)
fn void? Cpu.inst_div(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("dividing %s by %s", #dst, #src);
	$Type src = #src;
	if (src == 0) self.error("Cannot divide by zero");
	$Type res = #dst / src;
	self.set_val($width, inst, DST, res)!;
	self.flags.zero = res == 0;
}

fn void? Cpu.inst_idiv(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("dividing %s by %s", #dst, #src);
	$typefrom($width.itype) src = #src;
	if (src == 0) self.error("Cannot divide by zero");
	$typefrom($width.itype) res = ($typefrom($width.itype))#dst / src;
	self.set_val($width, inst, DST, ($Type)res)!;
	self.flags.zero = res == 0;
}

fn void? Cpu.inst_rem(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("getting remainder of %s and %s", #dst, #src);
	$Type src = #src;
	if (src == 0) self.error("Cannot divide by zero");
	$Type res = #dst % src;
	self.set_val($width, inst, DST, res)!;
	self.flags.zero = res == 0;
}

fn void? Cpu.inst_irem(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("getting remainder of %s and %s", #dst, #src);
	$typefrom($width.itype) src = #src;
	if (src == 0) self.error("Cannot divide by zero");
	$typefrom($width.itype) res = (($typefrom($width.itype))#dst) % src;
	self.set_val($width, inst, DST, ($Type)res)!;
	self.flags.zero = res == 0;
}


fn void? Cpu.inst_mov(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	// logger::info("moving %s into %s", src, #dst);
	logger::debug("Moving %s", #src);
	self.set_val($width, inst, DST, #src)!;
}

// Nice and jank :3
fn void? Cpu.inst_movz(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("MovZing %s", #src);
	uint src = #src;
	// TODO: this might not actually work because W32 is also used for offset calculation which could break things
	// self.set_val(W32, inst, DST, (uint)#src)!;
	uint offset = @arg_offset($width, inst, @inst_type(), DST);
	// io::printfn("Moving %.8x", src);
	switch (inst.dst)
	{
		case REG:
			self.regs[self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8)].write(W32, src);
		case REG_PTR:
			self.mem_get(self.regs[self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8)], BitWidth.W32)!.set(W32, src);
		case IMM:
			self.error("mov into immediate value not implemented");
		case IMM_PTR:
			self.mem_get(self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE)!.get(W32), BitWidth.W32)!.set(W32, src);
	}
}

fn void? Cpu.inst_cmp(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("Comparing %s and %s", #src, #dst);
	$Type src = #src;
	$Type dst = #dst;
	self.flags.zero = src == dst;
	self.flags.carry = src > dst;
}

fn void? Cpu.inst_jmp(&self, Instruction inst) @Inst => self.@setup(inst, W32, false; #src, #dst)
{
	logger::debug("Jmping to 0x%.8x", #src);
	// logger::info("Jmping to %.8x at %s", #src, self.cycles);
	// if (#src == 0xf0000c23) self.error("start of the loop");
	self.inst_ptr_next = #src;
}

fn void? Cpu.inst_rjmp(&self, Instruction inst) @Inst => self.@setup_w(inst, false; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("RJmping by %s", ($typefrom($width.itype))#src);
	self.inst_ptr_next = *self.inst_ptr + ($typefrom($width.itype))#src;// - common::INST_SIZE;
}

extern fn CInt putchar(CInt c);

// TODO: match https://github.com/fox32-arch/fox32/blob/main/src/bus.c#L164
fn void? Cpu.inst_out(&self, Instruction inst) @Inst => self.@setup(inst, W32; #src, #dst)
{
	uint dst = #dst;
	// logger::info("Out: src: %.8s (0x%.8x), dst: %.8s (0x%.8x)", #src, #src, dst, dst);


	switch (dst)
	{
		// serial port
		case 0:
			putchar((CInt)#src);
		// Framebuffer overlays
		case 0x80000000..0x8000031f:
			OverlayAddr opt = (OverlayAddr)dst;
			DisplayOverlay* over = &self.overlays[opt.idx];
			switch (opt.type)
			{
				case POSITION:
					SplitInt val = (SplitInt)#src;
					over.pos.x = val.first;
					over.pos.y = val.second;
				case SIZE:
					SplitInt val = (SplitInt)#src;
					over.size.x = val.first;
					over.size.y = val.second;
				case FB_PTR:
					over.fb_ptr = #src;
				case ENABLE:
					over.enable = #src != 0;
			}
		case 0x80001000..0x80005003:
			DiskCommandAddr opt = (DiskCommandAddr)dst;
			// logger::info("writing %s for disk %s", opt.command, opt.idx);
			switch (opt.command)
			{
				// buffer ptr
				case 0x20:
					disk::set_buffer(#src);
				// begin read
				case 0x30:
					disk::read(self, opt.idx, #src)!!;
				// begin write
				case 0x40:
					disk::write(self, opt.idx, #src)!!;
				// remove
				case 0x50:
					disk::remove(opt.idx)!!;
				// size + other
				default:
					self.error("Cannot write disk option %s with inst_out", opt.command);
			}
		// mouse buttons
		case 0x80000400:
			MouseState src = (MouseState)#src;
			(void)gui::mouse_state.@use(; #val)
			{
				// io::printfn("%s SET: button before: %.3b, value: %.32b", self.cycles, (uint)#val, (uint)#src);
				#val = {.pressed = src.pressed, .released = src.released, .held = src.held};
				// io::printfn("%s SET: button after: %.3b", self.cycles, (uint)#val);
			};
			// (void)gui::mouse_state.set({.pressed = src.pressed, .released = src.released, .held = src.held});
			// logger::info("mouse button state after out: %.32b", (uint)gui::mouse_state.get()!!);
			// (void)gui::mouse_state.set((MouseState)(#src | 0b111));
		// mouse position
		case 0x80000401:
			(void)gui::mouse_pos.set((SplitInt)#src);
		// Everything else
		default:
			logger::warn("Out to 0x%.8x is not supported yet", dst);
	}
}

// TODO: match https://github.com/fox32-arch/fox32/blob/main/src/bus.c#L30
fn void? Cpu.inst_in(&self, Instruction inst) @Inst => self.@setup(inst, W32; #src, #dst)
{
	// uh, there's something I think
	// looks like it's a dynamic method that can be switched at runtime
	// $Type dst = #dst;
	// $Type src = #src;
	// if (dst != 0) self.error("You can't do that");
	uint src = #src;
	// logger::info("In: src: %.8s (0x%.8x), dst: %.8s (0x%.8x)", src, src, #dst, #dst);

	switch (src)
	{
		// stdin/serial port
		case 0:
			self.set_val(W32, inst, DST, (uint)(io::stdin().read_byte()!!))!;
		// framebuffer overlays
		case 0x80000000..0x8000031f:
			OverlayAddr opt = (OverlayAddr)(uint)src;
			DisplayOverlay* over = &self.overlays[opt.idx];
			SplitInt ret_val @noinit;
			switch (opt.type)
			{
				case POSITION:
					ret_val = {over.pos.x, over.pos.y};
					assert((uint)ret_val == (uint)(over.pos.x | (over.pos.y << 16)), "this is how ryfox did it, so it needs to match");
					// logger::warn("returning position 0x%.8x", ret_value);
				case SIZE:
					ret_val = {over.size.x, over.size.y};
					// logger::warn("returning size 0x%.8x", ret_value);
				case FB_PTR:
					ret_val = (SplitInt)over.fb_ptr;
					// logger::warn("returning ptr 0x%.8x", ret_value);
				case ENABLE:
					ret_val = (SplitInt)((uint)over.enable);
					// logger::warn("returning state 0x%.8x", ret_value);
			}
			self.set_val(W32, inst, DST, (uint)ret_val)!;
		// mouse buttons
		case 0x80000400:
			/*MouseState ms = gui::mouse_state.get()!!;
			MouseState dst = (MouseState)#dst;
			io::printfn("GET: button before: %.3b, value before: %.32b", (uint)ms, (uint)dst);
			dst.pressed |= ms.pressed;
			dst.released |= ms.released;
			dst.held = ms.held;
			io::printfn("GET: value after: %.32b", (uint)dst);*/
			uint st = (uint)gui::mouse_state.get()!!;
			// io::printfn("%s GET: button state: %.3b", self.cycles, st);
			self.set_val(W32, inst, DST, st)!;
		// mouse position
		case 0x80000401:
			self.set_val(W32, inst, DST, (uint)gui::mouse_pos.get()!!)!;
			// TODO: proper error handling, maybe have a generic `if catch err = inst(), if inst != VM_EXCEPTION return inst?` to only ignore vm exceptions instead of @maydiscard
			// maybe in the @setup macro have something like this:
/*
	macro @setup(...; @body(...))
	{
		fault err = @catch(fn void?()
		{
			@body(...);
		}());
		if (err != VM_EXCEPTION) handle_error(err)!!; // handle_error panics if it can't handle the error (like a disk error) but does nothing if it can (like a page fault *unless* in exception handling already)
	}
	// this is quite similar to the C emulator error handling & would replace the existing system in a more robust way
*/
		// disks
		case 0x80001000..0x80005003:
			DiskCommandAddr opt = (DiskCommandAddr)src;
			// logger::info("In: src: %.8s (0x%.8x), dst: %.8s (0x%.8x)", src, src, #dst, #dst);
			// logger::info("reading %s from disk %s", opt.command, opt.idx);
			switch (opt.command)
			{
				// size
				case 0x10:
					self.set_val(W32, inst, DST, (uint)disk::size(opt.idx))!;
				// buffer ptr
				case 0x20:
					self.set_val(W32, inst, DST, disk::buffer())!;

				// everything else
				default:
					self.error("Cannot read disk option %s with inst_in", opt.command);
			}
		// read from key queue
		case 0x80000500:
			self.set_val(W32, inst, DST, gui::get_key())!;
		// RTC & uptime
		case 0x80000700..0x80000706:
			ClockOption opt = (ClockOption)src;
			TzDateTime time = datetime::now().to_local();
			switch (opt.type)
			{
				case YEAR:
					self.set_val(W32, inst, DST, (uint)time.year)!;
				case MONTH:
					self.set_val(W32, inst, DST, (uint)time.month.ordinal)!;
				case DAY:
					self.set_val(W32, inst, DST, (uint)time.day)!;
				case HOUR:
					self.set_val(W32, inst, DST, (uint)time.hour)!;
				case MINUTE:
					self.set_val(W32, inst, DST, (uint)time.min)!;
				case SECOND:
					self.set_val(W32, inst, DST, (uint)time.sec)!;
				case MS_SINCE_STARTUP:
					self.uptime += self.clock.mark();
					self.set_val(W32, inst, DST, (uint)self.uptime.to_ms())!;
				case DAYLIGHT_SAVINGS:
					Tm tm @noinit;
					Time_t time_t = (Time_t)time.time.to_seconds();
					libc::localtime_r(&time_t, &tm);
					assert(time.day == tm.tm_mday);
					assert(time.year == tm.tm_year + 1900);
					self.set_val(W32, inst, DST, (uint)tm.tm_isdst)!;


			}
		// other (TODO: once it's all implemented, make this an error (only if it's an error in the reference emulator)
		default:
			logger::warn("In from 0x%.8x is not supported yet", src);
			self.set_val(W32, inst, DST, (uint)0)!;
	}
}

fn void? Cpu.inst_call(&self, Instruction inst) @Inst => self.@setup(inst, W32, false; #src, #dst)
{
	// save the value before moving forward so I can push the right value and jmp to the right value
	uint src = #src;
	self.move_forward(W32, inst::CALL, inst);
	// logger::info("Calling %.8x at %s", src, self.cycles);
	self._push(W32, self.inst_ptr_next, false)!;
	logger::debug("Calling 0x%.8x", src);
	self.inst_ptr_next = src;
}

fn void? Cpu.inst_rcall(&self, Instruction inst) @Inst => self.@setup_w(inst, false; BitWidth $width, $Type, #src, #dst)
{
	// save the value before moving forward so I can push the right value and jmp to the right value
	$typefrom($width.itype) src = #src;
	self.move_forward($width, inst::RCALL, inst);
	self._push(W32, self.inst_ptr_next, false)!;
	logger::debug("RCalling by 0x%.8x", src);
	self.inst_ptr_next = *self.inst_ptr + src;
}


fn void? Cpu.inst_ret(&self, Instruction inst) @Inst => self.@setup(inst, W32, false; #src, #dst)
{
	uint src = self._pop(W32)!;
	logger::debug("Returning to 0x%.8x", src);
	self.inst_ptr_next = src;
}

fn void? Cpu.inst_reti(&self, Instruction inst) @Inst => self.@setup(inst, W32, false; #src, #dst)
{
	self.flags = (CpuFlags)self._pop(W8)!;
	self.inst_ptr_next = self._pop(W32)!;
	if (self.flags.swap_sp) self.error("swap_sp not implemented yet (reti)");
	if (self.flags.interrupt)
	{
		self.handle_deferred_interrupts();
	}
}

fn void? Cpu.inst_loop(&self, Instruction inst) @Inst => self.@setup(inst, W32, false; #src, #dst)
{
	if ((*self.loop_ptr -= 1) != 0)
	{
		logger::debug("Looping to 0x%.8x", #src);
		self.inst_ptr_next = #src;
	}
	else
	{
		logger::debug("Not looping");
		self.move_forward(W32, inst::LOOP, inst);
	}
}

fn void? Cpu.inst_rloop(&self, Instruction inst) @Inst => self.@setup_w(inst, false; BitWidth $width, $Type, #src, #dst)
{
	if ((*self.loop_ptr -= 1) != 0)
	{
		logger::debug("RLooping by %s", ($typefrom($width.itype))#src);
		self.inst_ptr_next = *self.inst_ptr + ($typefrom($width.itype))#src;
	}
	else
	{
		logger::debug("Not rlooping");
		self.move_forward(W32, inst::RLOOP, inst);
	}
}


fn void? Cpu.inst_push(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("Pushing %s %.8x", #src, #src);
	self._push($width, #src, false)!;
}

// TODO: I don't know if set_val(src) is correct, I should check it
fn void? Cpu.inst_pop(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	logger::debug("Popping into %s", #src);
	self.set_val($width, inst, SRC, self._pop($width)!)!;
}

fn void? Cpu.inst_not(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	$Type res = ~#src;
	self.set_val($width, inst, DST, res)!;
	self.flags.zero = res == 0;
}

fn void? Cpu.inst_sla(&self, Instruction inst) @Inst => @bit_op_inst(self, inst, op_sla);

fn void? Cpu.inst_sra(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	// TODO: 'macro bool Instruction.is_arg_signed($self, ArgPos)' to do this automatically
	$typefrom($width.itype) res = ($typefrom($width.itype))#dst >> ($typefrom($width.itype))#src;
	self.set_val($width, inst, DST, ($Type)res)!;
	self.flags.zero = res == 0;
}

fn void? Cpu.inst_srl(&self, Instruction inst) @Inst => @bit_op_inst(self, inst, op_srl);

fn void? Cpu.inst_bts(&self, Instruction inst) @Inst => self.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	$Type res = #dst & (1 << #src);
	self.flags.zero = res == 0;
}

fn void? Cpu.inst_bse(&self, Instruction inst) @Inst => @bit_op_inst(self, inst, op_bse);

fn void? Cpu.inst_bcl(&self, Instruction inst) @Inst => @bit_op_inst(self, inst, op_bcl);

fn void? Cpu.inst_or(&self, Instruction inst) @Inst => @bit_op_inst(self, inst, op_or);

fn void? Cpu.inst_and(&self, Instruction inst) @Inst => @bit_op_inst(self, inst, op_and);

fn void? Cpu.inst_xor(&self, Instruction inst) @Inst => @bit_op_inst(self, inst, op_xor);

fn void? Cpu.inst_rol(&self, Instruction inst) @Inst => @bit_op_inst(self, inst, op_rol);

// this isn't the same as InstructionType.is_bit_op. I should probably rename the other one, and this could also probably use a better name bc of how useful it could be for all the add/sub/etc instructions if it also set flags.carry
macro @bit_op_inst(Cpu* cpu, Instruction inst, #op) => cpu.@setup_w(inst; BitWidth $width, $Type, #src, #dst)
{
	$Type res = ($Type)#op(#dst, #src);
	cpu.set_val($width, inst, DST, res)!;
	cpu.flags.zero = res == 0;
}

macro op_or(a, b) => (a | b);
macro op_and(a, b) => (a & b);
macro op_bcl(a, b) => a & ~(1 << b);
macro op_bse(a, b) => a | (1 << b);
macro op_srl(a, b) => a >> b;
macro op_sla(a, b) => a << b;
macro op_xor(a, b) => a ^ b;
// $typeof(a) == $width.type (so basically it's a hack so I can resuse @bit_op_inst without needing to pass the width)
// <* @require x() *>
macro op_rol(a, b) => (a << b) | (a >> (($typeof(a).sizeof * 8) - b));
macro op_ror(a, b) => (a >> b) | (a << (($typeof(a).sizeof * 8) - b));

// fn bool x() => abort("rol");
