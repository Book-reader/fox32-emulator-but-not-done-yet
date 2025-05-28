module emulator;
import common;
import logger;

import std::io;
import std::thread;
import std::time;
import std::collections::list;
import std::math;

alias alloc = allocator::mem;

alias Register = uint;

macro Register.write(&self, BitWidth $width, data)
{
	logger::debug("Writing %s (0x%x) as %s", data, data, $width);
	self.$eval("write_" +++ $width.nameof)(data);
	logger::debug("Self is now %s (0x%x)", *self, *self);
}

fn void Register.write_W8(&self, char data) => *self = (*self & ~0x000000ff) | @as(uint, data);

fn void Register.write_W16(&self, ushort data) => *self = (*self & ~0x0000ffff) | @as(uint, data);

fn void Register.write_W32(&self, uint data) => *self = data;

macro Register.read(&self, BitWidth $width) => self.$eval("read_" +++ $width.nameof)();

fn char Register.read_W8(self) => @as(char, self & 0x000000ff);

fn ushort Register.read_W16(self) => @as(ushort, self & 0x0000ffff);

fn uint Register.read_W32(self) => self;

bitstruct CpuFlags : char
{
	bool zero : 0;
	bool carry : 1;
	bool interrupt : 3;
	bool exception_sp : 2;
}

struct Cpu
{
	// The address of the current instruction in memory
	Register* loop_ptr; // A pointer to regs[31];
	Register* stack_ptr; // A pointer to regs[32];
	Register* exception_ptr; // A pointer to regs[33];
	Register* frame_ptr; // A pointer to regs[34];
	Register* inst_ptr; // a pointer to regs[35];
	Register inst_ptr_next;
	CpuFlags flags;
	bool mmu_enabled;
	bool page_directory;
	Register[common::NUM_REGISTERS] regs;
	usz cycles;
	char[] ram;
	char[] rom;
}

<*
	@require len == buf.len
*>
fn void Cpu.mem_set(&self, uint start, uint len, char[] buf)
{
	// cannot have overlap
	if (start < common::RAM_SIZE && start + len - 1 <= common::RAM_SIZE)
	{
		self.ram[start:len] = buf[:len];
	}
	else if (start >= common::ROM_START && start + len - 1 <= common::ROM_START + common::ROM_SIZE)
	{
		self.rom[start-common::ROM_START:len] = buf[:len];
	}
	else
	{
		self.error("Out of range: 0x%.8x:%s", start, len);
	}
}

<*
	@ensure return.len == len
*>
fn char[] Cpu.mem_get(&self, uint start, uint len)
{
	// cannot have overlap
	if (start < common::RAM_SIZE && start + len - 1 <= common::RAM_SIZE)
	{
		return self.ram[start:len];
	}
	else if (start >= common::ROM_START && start + len - 1 <= common::ROM_START + common::ROM_SIZE)
	{
		return self.rom[start-common::ROM_START:len];
	}
	else
	{
		self.error("Out of range: 0x%.8x:%s", start, len);
	}
}

// TODO: maybe make current instruction part of the cpu struct?
// upside: passing less data around through stack
// downside: need to dereference to get it, may negate performance benefit, will need to check eventually
macro Cpu.print_instr(&self, Instruction inst, BitWidth $width, InstructionType $type, String $inst_name) => @pool()
{
	DString str;
	str.tinit();
	str.appendf("SP=%.8X IP=%.8X %-6s %s %-5s", *self.stack_ptr, *self.inst_ptr, inst.cond.name, $width.name, $inst_name);
	$switch $type.arg_count():
		$case 0:
			// TODO: feature request $break (check if exists first)
			0;
		$case 1:
			str.appendf(" %s", inst.src.fox32name);
			// TODO: report poor error messages when `@body(#src, #dst)` instead
			self.print_arg(&str, inst, $type, $width, SRC);
		$case 2:
			str.appendf(" %s", inst.src.fox32name);
			self.print_arg(&str, inst, $type, $width, SRC);
			str.appendf(",");
			str.appendf(" %s", inst.dst.fox32name);
			self.print_arg(&str, inst, $type, $width, DST);
		$default:
			$error("a");
	$endswitch
	io::printfn(str.str_view());
}

macro Cpu.print_arg(&self, DString* str, Instruction inst, InstructionType $inst_type, BitWidth $width, ArgPos $arg)
{
	uint offset = @arg_offset($width, inst, $inst_type, $arg);
	// logger::info("test: %s %s %s %s", $inst_type, $arg, $inst_type.is_bit_op(), offset);
	switch (inst.$eval($arg.name))
	{
		case REG:
		case REG_PTR:
			str.appendf(" %-8s", common::REG_NAMES[self.mem_get(self.inst_ptr_next + offset, 1).get(W8)]);
		case IMM:
		case IMM_PTR:
			str.appendf(" %.8X", self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE).get($width));
	}
}

fn void Cpu.init(&self)
{
	self.regs = {};
	self.loop_ptr = &self.regs[31];
	self.stack_ptr = &self.regs[32];
	self.exception_ptr = &self.regs[33];
	self.frame_ptr = &self.regs[34];
	self.inst_ptr = &self.regs[35];
	*self.inst_ptr = common::DEFAULT_INST_PTR;
	*self.stack_ptr = common::DEFAULT_STACK_PTR;
	self.inst_ptr_next = *self.inst_ptr;
	self.mmu_enabled = true;

	self.ram = mem::new_array(char, common::RAM_SIZE);
	self.rom = mem::new_array(char, common::ROM_SIZE);
}

fn void Cpu.deinit(&self)
{
	mem::free(self.ram);
	mem::free(self.rom);
	*self = {};
}

macro Cpu.error(&self, String fmt, ...)
{
	io::eprintfn("[ERROR] (%s) At cycle %s", $$FUNC, self.cycles);
	io::eprintf("[ERROR] At instruction %.8x -> %s\n[ERROR] ", *self.inst_ptr, (Instruction)self.mem_get(*self.inst_ptr, 2).get(W16));
	io::eprintfn(fmt, $vasplat);
	foreach (i, reg : self.regs)
	{
		logger::info("%s: %.8x", common::REG_NAMES[i], reg);
	}
	abort();
}

// TODO: multithreading by sending data between cpu structs with an array and a mutex
//tlocal Cpu cpu;

// TODO: make all get instructions return a char[] so I can just do 'get_arg1()[:len] = get_arg2()[:len]' instead of all the bitmasks and switch statements and macros
// it will make memory to memory operations faster & I can have a reg->reg version as well
fn int main(String[] args)
{
	Cpu cpu;
	cpu.init();
	defer cpu.deinit();

	char[] prog;

	usz max_cycles;

	if (args.len > 1)
	{
/*		if (args[0] == "test")
		{
			prog = args[1];
		}
		else
		{*/
		prog = file::load(alloc, args[1])!!;

		if (args.len > 2)
		{
			max_cycles = args[2].to_int()!!;
		}
//		}
	}
	else
	{
		prog = x"340301ff00000000000000330000013c000003030101000000000000001c0000001503e8ffffffffffffff3b033a03";
	}
	defer if (args.len > 1 && args[0] != "test") free(prog);


	cpu.mem_set(common::DEFAULT_INST_PTR, prog.len, prog);

	logger::debug("Executing (%s b): %h", prog.len, prog[:prog.len < 200 ? prog.len : 200]);

	bool running = true;


	$if $feature(PERF):
		uint iterations = 0;
		Clock clock = clock::now();
	$endif

	Instruction inst;
//	while (running)
	{
		// TODO: maybe make each Cpu.inst_... a function in an associated value for an enum, so I could just do inst.execute()
		// it wouldn't work with the exit instructions tho... and might require multiple levels of switching/indexing so may not be better
		switch (inst::GET_) @jump
		{
			case inst::NOP:
				logger::panic("Reached NOP (does not exist in fox32rom)");
				nextcase;
			case inst::GET:
				cpu.cycles ++;
				if (cpu.cycles == max_cycles)
				{
					logger::info("Hit max_cycles of %s, exiting", max_cycles);
					nextcase inst::BREAK;
				}
				// TODO: set a clock speed
				$if $feature(DELAY):
					thread::sleep(1000000);
				$endif
				*cpu.inst_ptr = cpu.inst_ptr_next;

				nextcase;
			case inst::GET_:
				$if $feature(PERF):
					iterations ++;
					if (iterations % 30000000 == 0)
					{
						NanoDuration t = clock.mark();
						logger::info("%s cycles took %s (%s)", iterations, t, t.to_sec() <= 1 ? "good" : "bad");
						iterations = 0;
						clock = clock::now();
					}
				$endif
				logger::debug("Nearby mem: %s", cpu.mem_get(*cpu.inst_ptr, 10));
				
				inst = (Instruction)cpu.mem_get(*cpu.inst_ptr, 2).get(W16);

				logger::debug("%s 0x%.8x -> %s", cpu.cycles, *cpu.inst_ptr, inst);

				// Point at the next byte
				cpu.inst_ptr_next = *cpu.inst_ptr + common::INST_SIZE;

				// Execute the current instruction
				nextcase inst.type;
			case inst::BRK:
				static usz counter = 0;
				counter ++;
				logger::warn("Reached breakpoint at cycle %s, addr 0x%.8x", cpu.cycles, *cpu.inst_ptr);
				if (counter == 2) cpu.error("Second breakpoint");
				nextcase inst::GET;
			case inst::HALT:
			case inst::BREAK:
				logger::info("Exiting after %s clock cycles", cpu.cycles);
				foreach (i, reg : cpu.regs)
				{
					logger::info("%s: %.8x", common::REG_NAMES[i], reg);
				}
				return 0;

			case inst::INC:
				cpu.inst_inc(inst);
				nextcase inst::GET;
			case inst::DEC:
				cpu.inst_dec(inst);
				nextcase inst::GET;
			case inst::ADD:
				cpu.inst_add(inst);
				nextcase inst::GET;
			case inst::SUB:
				cpu.inst_sub(inst);
				nextcase inst::GET;
			case inst::MUL:
				cpu.inst_mul(inst);
				nextcase inst::GET;
			case inst::DIV:
				cpu.inst_div(inst);
				nextcase inst::GET;
			case inst::REM:
				cpu.inst_rem(inst);
				nextcase inst::GET;
			case inst::IREM:
				cpu.inst_irem(inst);
				nextcase inst::GET;
			case inst::MOV:
				cpu.inst_mov(inst);
				nextcase inst::GET;
			case inst::MOVZ:
				// TODO: merge with inst_mov using generic
				cpu.inst_movz(inst);
				nextcase inst::GET;
			case inst::CMP:
				cpu.inst_cmp(inst);
				nextcase inst::GET;
			case inst::JMP:
				cpu.inst_jmp(inst);
				nextcase inst::GET;
			case inst::RJMP:
				cpu.inst_rjmp(inst);
				nextcase inst::GET;
			case inst::MCL:
				cpu.mmu_enabled = false;
				nextcase inst::GET;
			case inst::MSE:
				cpu.mmu_enabled = true;
				nextcase inst::GET;
			case inst::OUT:
				cpu.inst_out(inst);
				nextcase inst::GET;
			case inst::IN:
				cpu.inst_in(inst);
				nextcase inst::GET;
			case inst::CALL:
				cpu.inst_call(inst);
				nextcase inst::GET;
			case inst::RET:
				cpu.inst_ret(inst);
				nextcase inst::GET;
			case inst::ISE:
				cpu.flags.interrupt = true;
				logger::error("Interrupts don't work yet :3");
				nextcase inst::GET;
			case inst::ICL:
				cpu.flags.interrupt = false;
				nextcase inst::GET;
			case inst::LOOP:
				cpu.inst_loop(inst);
				nextcase inst::GET;
			case inst::PUSH:
				cpu.inst_push(inst);
				nextcase inst::GET;
			case inst::POP:
				cpu.inst_pop(inst);
				nextcase inst::GET;
			case inst::SLA:
				cpu.inst_sla(inst);
				nextcase inst::GET;
			case inst::SRA:
				cpu.inst_sra(inst);
				nextcase inst::GET;
			case inst::OR:
				cpu.inst_or(inst);
				nextcase inst::GET;
			case inst::AND:
				cpu.inst_and(inst);
				nextcase inst::GET;
			default:
				cpu.error("Instruction %s is not implemented yet", inst.type.get_name());
				nextcase inst::BREAK;
		}
	}
}

// NOTE: #src and #dst are FUNCTIONS that will be called EVERY TIME they are used
// this is fine when debug printing is enabled, but not otherwise
fn void Cpu.inst_inc(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("Incrementing %s", #src);
	$typefrom($width.type) res @noinit;

	self.flags.carry = math::overflow_add(#src, ($typefrom($width.type))(1 << inst.dst.ordinal), &res);
	self.flags.zero = res == 0;

	self.set_val($width, inst, SRC, res);
}

fn void Cpu.inst_dec(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("Decrementing %s", #src);
	$typefrom($width.type) res @noinit;
	$typefrom($width.type) src = #src;
	bool over = math::overflow_sub(src, ($typefrom($width.type))(1 << inst.dst.ordinal), &res);
	self.set_val($width, inst, SRC, res);
	self.flags.carry = over;
	self.flags.zero = res == 0;
	// logger::info("Decrementing %s by %s (%s) = %s; carry: %s, zero: %s", src, (1 << inst.dst.ordinal), inst.dst, res, self.flags.carry, self.flags.zero);
}

fn void Cpu.inst_add(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("Adding %s and %s", #dst, #src);
	$typefrom($width.type) res @noinit;
	// This also sets res
	self.flags.carry = math::overflow_add(#dst, #src, &res);
	self.flags.zero = res == 0;
	self.set_val($width, inst, DST, res);

	// if (res == 0x04000000) self.error("Encountered 0x04000000 (bad)");
}

fn void Cpu.inst_sub(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("Subtracting %s and %s", #dst, #src);
	$typefrom($width.type) res @noinit;
	// This also sets res
	self.flags.carry = math::overflow_sub(#dst, #src, &res);
	self.flags.zero = res == 0;
	self.set_val($width, inst, DST, res);
}

fn void Cpu.inst_mul(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("multiplying %s and %s", #dst, #src);
	$typefrom($width.type) res @noinit;
	// This also sets res
	self.flags.carry = math::overflow_mul(#dst, #src, &res);
	self.flags.zero = res == 0;
	self.set_val($width, inst, DST, res);
}

// TODO: merge div, idiv, rem, irem, etc with a macro/generic that just replaces the operand and type (signed vs unsigned)
fn void Cpu.inst_div(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("dividing %s by %s", #dst, #src);
	$typefrom($width.type) src = #src;
	if (src == 0) self.error("Cannot divide by zero");
	$typefrom($width.type) res = #dst / src;
	self.set_val($width, inst, DST, res);
	self.flags.zero = res == 0;
}

fn void Cpu.inst_rem(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("getting remainder of %s and %s", #dst, #src);
	$typefrom($width.type) src = #src;
	if (src == 0) self.error("Cannot divide by zero");
	$typefrom($width.type) res = #dst % src;
	self.set_val($width, inst, DST, res);
	self.flags.zero = res == 0;
}

fn void Cpu.inst_irem(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("getting remainder of %s and %s", #dst, #src);
	$typefrom($width.itype) src = #src;
	if (src == 0) self.error("Cannot divide by zero");
	$typefrom($width.itype) res = (($typefrom($width.itype))#dst) % src;
	self.set_val($width, inst, DST, ($typefrom($width.type))res);
	self.flags.zero = res == 0;
}


fn void Cpu.inst_mov(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	// logger::info("moving %s into %s", src, #dst);
	logger::debug("Moving %s", #src);
	self.set_val($width, inst, DST, #src);
}

// Nice and jank :3
fn void Cpu.inst_movz(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("MovZing %s", #src);
	uint src = #src;
	// TODO: this might not actually work because W32 is also used for offset calculation which could break things
	// self.set_val(W32, inst, DST, (uint)#src);
	uint offset = @arg_offset($width, inst, @inst_type(), DST);
	// io::printfn("Moving %.8x", src);
	switch (inst.dst)
	{
		case REG:
			self.regs[self.mem_get(self.inst_ptr_next + offset, 1).get(W8)].write(W32, src);
		case REG_PTR:
			self.mem_get(self.regs[self.mem_get(self.inst_ptr_next + offset, 1).get(W8)], BitWidth.W32).set(W32, src);
		case IMM:
			self.error("mov into immediate value not implemented");
		case IMM_PTR:
			self.mem_get(self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE).get(W32), BitWidth.W32).set(W32, src);
	}
}

fn void Cpu.inst_cmp(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("Comparing %s and %s", #src, #dst);
	$typefrom($width.type) src = #src;
	$typefrom($width.type) dst = #dst;
	self.flags.zero = src == dst;
	self.flags.carry = src > dst;
}

fn void Cpu.inst_jmp(&self, Instruction inst) @inline => self.@setup(inst, W32, false; #src, #dst)
{
	logger::debug("Jmping to 0x%.8x", #src);
	// logger::info("Jmping to %.8x at %s", #src, self.cycles);
	// if (#src == 0xf0000c23) self.error("start of the loop");
	self.inst_ptr_next = #src;
}

fn void Cpu.inst_rjmp(&self, Instruction inst) @inline => self.@setup_w(inst, false; BitWidth $width, #src, #dst)
{
	logger::debug("Jmping by %s", (int)#src);
	self.inst_ptr_next = *self.inst_ptr + (int)#src;// - common::INST_SIZE;
}

extern fn CInt putchar(CInt c);

// TODO: match https://github.com/fox32-arch/fox32/blob/main/src/bus.c#L164
fn void Cpu.inst_out(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	$typefrom($width.type) dst = #dst;

	if (dst != 0)
	{
		logger::warn("Out to not stdout is not supported yet: 0x%.8x", dst);
	}
	else
	{
		putchar((CInt)#src);
	}
}

// TODO: match https://github.com/fox32-arch/fox32/blob/main/src/bus.c#L30
fn void Cpu.inst_in(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	// uh, there's something I think
	// looks like it's a dynamic method that can be switched at runtime
	// $typefrom($width.type) dst = #dst;
	// $typefrom($width.type) src = #src;
	// if (dst != 0) self.error("You can't do that");
	$typefrom($width.type) src = #src;

	if (src != 0)
	{
		logger::warn("In from not stdin is not supported yet: 0x%.8x", src);
	}
	else
	{
		self.set_val($width, inst, DST, ($typefrom($width.type))(io::stdin().read_byte()!!));
	}
}

fn void Cpu.inst_call(&self, Instruction inst) @inline => self.@setup(inst, W32, false; #src, #dst)
{
	/*if (*self.inst_ptr >= 0xf0000757 - 2u && *self.inst_ptr <= 0xf0000757 + 2u)
	{
		logger::info("---------------------------------");
	io::eprintfn("[INFO] At cycle %s", self.cycles);
	io::eprintfn("[INFO] At instruction %.8x -> %s", *self.inst_ptr, (Instruction)self.mem_get(*self.inst_ptr, 2).get(W16));
		foreach (i, reg : self.regs)
		{
			logger::info("%s: %.8x", common::REG_NAMES[i], reg);
		}
	}*/
	// save the value before moving forward so I can push the right value and jmp to the right value
	uint src = #src;
	self.move_forward(W32, inst::CALL, inst);
	// logger::info("Calling %.8x at %s", src, self.cycles);
	self._push(W32, self.inst_ptr_next, false);
	logger::debug("Calling 0x%.8x", src);
	self.inst_ptr_next = src;
}

fn void Cpu.inst_ret(&self, Instruction inst) @inline => self.@setup(inst, W32, false; #src, #dst)
{
	$typefrom(BitWidth.W32.type) src = self._pop(W32);
	logger::debug("Returning to 0x%.8x", src);
	// logger::info("Returning to %.8x at %s", src, self.cycles);
	self.inst_ptr_next = src;
}

fn void Cpu.inst_loop(&self, Instruction inst) @inline => self.@setup(inst, W32, false; #src, #dst)
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

fn void Cpu.inst_push(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("Pushing %s %.8x", #src, #src);
	self._push($width, #src, false);
}

// TODO: I don't know if set_val(src) is correct, I should check it
fn void Cpu.inst_pop(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	logger::debug("Popping into %s", #src);
	self.set_val($width, inst, SRC, self._pop($width));
}

fn void Cpu.inst_sla(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	// bit manipulation instructions always have W8 src bc 255 > 32bits
	$typefrom($width.type) res = #dst << #src;

	// self.error("sla: src = %.8x, dst = %.8x, dst << src = %.8x, (dst) << (src) = %.8x", #src, #dst, res, (#dst) << (#src));

	self.set_val($width, inst, DST, res);
	self.flags.zero = res == 0;
}

fn void Cpu.inst_sra(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	// TODO: 'macro bool Instruction.is_signed($self)' to do this automatically
	$typefrom($width.itype) res = ($typefrom($width.itype))#dst >> ($typefrom($width.itype))#src;
	self.set_val($width, inst, DST, ($typefrom($width.type))res);
	self.flags.zero = res == 0;
}

fn void Cpu.inst_or(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	$typefrom($width.type) res = #dst | #src;
	self.set_val($width, inst, DST, res);
	self.flags.zero = res == 0;
}

fn void Cpu.inst_and(&self, Instruction inst) @inline => self.@setup_w(inst; BitWidth $width, #src, #dst)
{
	$typefrom($width.type) res = #dst & #src;
	self.set_val($width, inst, DST, res);
	self.flags.zero = res == 0;
}


macro bool Cpu.should_execute(&self, Instruction inst)
{
	// TODO: @jump?
	switch (inst.cond)
	{
		case ALWAYS:
			return true;
		case IFZ:
			return self.flags.zero;
		case IFNZ:
			return !self.flags.zero;
		case IFC: // same as: IFLT
			return self.flags.carry; 
		case IFNC: // same as: IFGTEQ
			return !self.flags.carry;
		case IFGT:
			return !self.flags.zero && !self.flags.carry;
		case IFLTEQ:
			return self.flags.zero || self.flags.carry;
	}
}

macro Cpu._push(&self, BitWidth $width, val, bool $is_bytes)
{
	*self.stack_ptr -= $width;
	$if $is_bytes:
		self.mem_set(*self.stack_ptr, $width, val);
	$else
		self.mem_get(*self.stack_ptr, $width).set($width, val);
	$endif
}

macro Cpu._pop(&self, BitWidth $width)
{
	var ret = self.mem_get(*self.stack_ptr, $width).get($width);
	*self.stack_ptr += $width;
	return ret;
}

macro Cpu.@setup_w(&self, Instruction inst, bool $move = true; @body(BitWidth $width, #src, #dst))
{
	@each_width(inst.width; BitWidth $width)
	{
		self.@setup(inst, $width, $move; #src, #dst)
		{
			@body($width, #src, #dst);
		};
	};
}

macro Cpu.@setup(&self, Instruction inst, BitWidth $width, bool $move = true; @body(#src, #dst))
{
	String $inst_name = @inst_name();
	InstructionType $type = @inst_type();
	// TODO: guard behind some sort of if condition
	// self.print_instr(inst, $width, $type, $inst_name);
	if (self.should_execute(inst))
	{
		self.@args(inst, $inst_name, $type, $width; #src, #dst)
		{
			@body(#src, #dst);
		};
	}
	else
	{
		$if !$move:
			self.move_forward($width, $type, inst);
		$endif
		logger::debug("Skipping instruction %s", inst);
		// logger::info("Skipping instruction %s", inst);
	}
	$if $move:
		self.move_forward($width, $type, inst);
	$endif
}

macro Cpu.@args(&self, Instruction inst, String $inst_name, InstructionType $type, BitWidth $width; @body(#src, #dst))
{
	$switch $type.arg_count():
		$case 0:
			@body(no_params($inst_name, SRC), @no_param($inst_name, DST));
		$case 1:
			// $typefrom($width.type) src = self.get_val($width, inst, SRC);
			// @body(src, no_param($type, DST));
			@body(self.get_val($width, inst, SRC), no_param($inst_name, DST));
		$case 2:
			$if $type.is_bit_op():
				// $typefrom($width.type) src = self.get_val(W8, inst, SRC);
				@body(self.get_val(W8, inst, SRC), self.get_val($width, inst, DST));
			$else
				// $typefrom($width.type) src = self.get_val($width, inst, SRC);
				@body(self.get_val($width, inst, SRC), self.get_val($width, inst, DST));
			$endif
			// $typefrom($width.type) dst = self.get_val($width, inst, DST);
			// @body(src, dst);
		$default:
			$error("What");
	$endswitch
}

// only to be used in the above Cpu.@args
macro no_param(String $inst_name, ArgPos $pos) { $error("Instruction " +++ $inst_name +++ " does not have parameter " +++ $pos.name); }

<*
	@require $typeof(val).typeid == $width.type
*>
macro Cpu.set_val(&self, BitWidth $width, Instruction inst, ArgPos $arg, val, InstructionType $inst_type = @inst_type())
{
	uint offset = @arg_offset($width, inst, $inst_type, $arg);
	// io::printfn("Moving %.8x", val);
	// logger::debug("Current idx is %s, calculated offset is %s", self.inst_ptr_next, offset);
	switch (inst.$eval($arg.name))
	{
		case REG:
			char reg = self.mem_get(self.inst_ptr_next + offset, 1).get(W8);
			/*if (reg == 7)
			{
				logger::info("Writing %s (%.8x) into R1", val, val);
				if (val == uint.min - 1u)
				{
					self.error("Underflow :(");
				}
			}*/
			self.regs[reg].write($width, val);
		case REG_PTR:
			char reg = self.mem_get(self.inst_ptr_next + offset, 1).get(W8);
			uint smol_offset = !inst.has_offset ? 0 : self.mem_get(self.inst_ptr_next + offset + 1, 1).get(W8);
			self.mem_get(self.regs[reg] + smol_offset, $width).set($width, val);
			// self.mem_get(self.regs[self.mem_get(self.inst_ptr_next + offset, 1).get(W8)], $width).set($width, val);
		case IMM:
			self.error("mov into immediate value not implemented");
		case IMM_PTR:
			self.mem_get(self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE).get(W32), $width).set($width, val);
	}
}

<*
	@ensure $typeof(return).typeid == $width.type
*>
macro Cpu.get_val(&self, BitWidth $width, Instruction inst, ArgPos $arg, InstructionType $inst_type = @inst_type())
{
	uint offset = @arg_offset($width, inst, $inst_type, $arg);
	// logger::debug("Current idx is %s, calculated offset is %s", self.inst_ptr_next, offset);
	switch (inst.$eval($arg.name))
	{
		case REG:
			logger::debug("Reading from register %s", common::REG_NAMES[self.mem_get(self.inst_ptr_next + offset, 1).get(W8)]);
			return self.regs[self.mem_get(self.inst_ptr_next + offset, 1).get(W8)].read($width);
		case REG_PTR:
			char reg = self.mem_get(self.inst_ptr_next + offset, 1).get(W8);
			uint smol_offset = !inst.has_offset ? 0 : self.mem_get(self.inst_ptr_next + offset + 1, 1).get(W8);
			$typefrom($width.type) val = self.mem_get(self.regs[reg] + smol_offset, $width).get($width);
			return val;// self.mem_get(self.regs[reg] + self.mem_get(self.inst_ptr_next + 1, 1).get(W8), $width).get($width);
		case IMM:
			return self.mem_get(self.inst_ptr_next + offset, $width).get($width);
		case IMM_PTR:
			return self.mem_get(self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE).get(W32), $width).get($width);
	}
}

macro void @each_width(BitWidth width; @body(BitWidth $width))
{
	switch (width)
	{
		case W8:
			@body(W8);
		case W16:
			@body(W16);
		case W32:
			@body(W32);
	}
}

// TODO: consider using this once I have more things as generic functions
// macro void @earch_arg(ArgType type; @body(ArgType $type))

macro @as_width(BitWidth $width, #expr, bool $signed = false)
{
	$if $signed:
		return @as($typefrom($width.itype), #expr);
	$else
		return @as($typefrom($width.type), #expr);
	$endif
}

macro Cpu.move_forward(&self, BitWidth $width, InstructionType $type, Instruction inst)
{
	$switch $type.arg_count():
		$case 1:
			self.inst_ptr_next += arg_size(inst, $type, SRC, $width);
		$case 2:
			self.inst_ptr_next += arg_size(inst, $type, SRC, $width);
			self.inst_ptr_next += arg_size(inst, $type, DST, $width);
		$case 0:
			return;
		$default:
			$error("No");
	$endswitch
}

macro uint arg_size(Instruction inst, InstructionType $type, ArgPos $arg, BitWidth $width)
{
	switch (inst.$eval($arg.name))
	{
		case REG:
			return 1;
		case REG_PTR:
			if (@unlikely(inst.has_offset))
			{
				return 2;
			}
			else
			{
				return 1;
			}
		case IMM:
			$if $type.is_bit_op() && $arg == SRC:
				return 1;
			$else
				return $width.size;
			$endif
		case IMM_PTR:
			return common::PTR_SIZE;
	}
}

macro uint @arg_offset(BitWidth $width, Instruction inst, InstructionType $type, ArgPos $arg) => @select($arg == SRC, 0, arg_size(inst, $type, SRC, $width));

enum ArgPos : (String name)
{
	SRC = "src",
	DST = "dst",
}

<*
 @require $$FUNC[0:9] == "Cpu.inst_" : "@inst_name must be called from inside a cpu instruction"
*>
macro String @inst_name() => @str_upper($$FUNC[9..]);

<*
 @require $$FUNC[0:9] == "Cpu.inst_" : "@inst_type must be called from inside a cpu instruction"
*>
macro InstructionType @inst_type() => $eval("inst::" +++ @inst_name());
