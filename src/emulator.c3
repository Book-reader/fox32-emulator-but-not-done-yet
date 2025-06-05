module emulator;
import common;
import logger;
import gui;

import std::io;
import std::thread;
import std::time;
import std::collections::list;
import std::math;

alias alloc = allocator::mem;

alias Register = uint;

macro Register.write(&self, BitWidth $width, data)
{
	$switch $width:
	$case W8:
		*self = (*self & ~0x000000ff) | @as(uint, data);
	$case W16:
		*self = (*self & ~0x0000ffff) | @as(uint, data);
	$case W32:
		*self = data;
	$endswitch
}

macro Register.read(self, BitWidth $width)
{
	$switch $width:
	$case W8:
		return @as(char, self & 0x000000ff);
	$case W16:
		return @as(ushort, self & 0x0000ffff);
	$case W32:
		return self;
	$endswitch
}

bitstruct CpuFlags : char
{
	bool zero : 0;
	bool carry : 1;
	bool interrupt : 2;
	bool swap_sp : 3;
}

struct DisplayOverlay
{
	uint[<2>] pos;
	uint[<2>] size;
	uint fb_ptr;
	bool enable;
}

bitstruct OverlayAddr : uint @littleendian
{
	char idx : 0..7;
	OverlayOption type : 8..15;
}

bitstruct SplitInt : uint @littleendian
{
	uint first : 0..15;
	uint second : 16..31;
}

enum OverlayOption : char
{
	POSITION,
	SIZE,
	FB_PTR,
	ENABLE,
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
	DisplayOverlay[common::NUM_OVERLAYS] overlays;
	bool[common::NUM_VECTORS] deferred_vectors;
	bool exception;
	Interrupt exception_type;
}

<*
	@require len == buf.len
*>
fn void? Cpu.mem_set(&self, uint start, uint len, char[] buf)
{
	// cannot have overlap
	if (start < common::RAM_SIZE && start + len - 1 < common::RAM_SIZE)
	{
		self.ram[start:len] = buf[:len];
	}
	else if (start >= common::ROM_START && start + len - 1 < common::ROM_START + common::ROM_SIZE)
	{
		self.rom[start-common::ROM_START:len] = buf[:len];
	}
	else
	{
		return self.throw(inter::EXC_PAGE_FAULT_WRITE)?;
	}
}

<*
	@ensure return.len == len
*>
fn char[]? Cpu.mem_get(&self, uint start, uint len)
{
	// cannot have overlap
	if (start < common::RAM_SIZE && start + len - 1 < common::RAM_SIZE)
	{
		return self.ram[start:len];
	}
	else if (start >= common::ROM_START && start + len - 1 < common::ROM_START + common::ROM_SIZE)
	{
		return self.rom[start-common::ROM_START:len];
	}
	else
	{
		return self.throw(inter::EXC_PAGE_FAULT_READ)?;
		//unreachable();
	}
}

// TODO: maybe make current instruction part of the cpu struct?
// upside: passing less data around through stack
// downside: need to dereference to get it, may negate performance benefit, will need to check eventually
macro Cpu.print_instr(&self, Instruction inst, BitWidth $width, InstructionType $type, String $inst_name) => @pool()
{
	// static char[256] buf;
	DString str;
	// str.init(allocator::wrap(&buf));
	/*str.appendf*/io::printf("SP=%.8X IP=%.8X %-6s %s %-5s ", *self.stack_ptr, *self.inst_ptr, inst.cond.name, $width.name, $inst_name);
	$switch $type.arg_count():
		$case 0:
			// TODO: feature request $break (check if exists first)
			0;
		$case 1:
			// str.appendf(" %s", inst.src.fox32name);
			io::print(inst.src.fox32name);
			// TODO: report poor error messages when `@body(#src, #dst)` instead
			self.print_arg(&str, inst, $type, $width, SRC)!!;
		$case 2:
			// str.appendf(" %s", inst.src.fox32name);
			io::print(inst.src.fox32name);
			self.print_arg(&str, inst, $type, $width, SRC)!!;
			// str.appendf(",");
			io::print(", ");
			// str.appendf(" %s", inst.dst.fox32name);
			io::print(inst.dst.fox32name);
			self.print_arg(&str, inst, $type, $width, DST)!!;
		$default:
			$error("a");
	$endswitch
	io::printn();
	//io::printn(str.str_view());
}

macro Cpu.print_arg(&self, DString* str, Instruction inst, InstructionType $inst_type, BitWidth $width, ArgPos $arg)
{
	uint offset = @arg_offset($width, inst, $inst_type, $arg);
	// logger::info("test: %s %s %s %s", $inst_type, $arg, $inst_type.is_bit_op(), offset);
	switch (inst.$eval($arg.name))
	{
		case REG:
		case REG_PTR:
			// str.appendf(" %-8s", common::REG_NAMES[self.mem_get(self.inst_ptr_next + offset, 1).get(W8)]);
			io::printf(" %-8s", common::REG_NAMES[self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8)]);
		case IMM:
		case IMM_PTR:
			//str.appendf(" %.8X", self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE).get($width));
			io::printf(" %.8X", self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE)!.get($width));
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

//	self.fb.init();
}

fn void Cpu.deinit(&self)
{
	mem::free(self.ram);
	mem::free(self.rom);
//	self.fb.free();
	*self = {};
}

macro Cpu.error(&self, String fmt, ...)
{
	io::eprintfn("[ERROR] (%s) At cycle %s", $$FUNC, self.cycles);
	io::eprintf("[ERROR] At instruction %.8x -> %s\n[ERROR] ", *self.inst_ptr, (Instruction)self.mem_get(*self.inst_ptr, 2)!!.get(W16));
	io::eprintfn(fmt, $vasplat);
	foreach (i, reg : self.regs)
	{
		logger::info("%s: %.8x", common::REG_NAMES[i], reg);
	}
	abort();
}

/*macro CpuState.@get(#self; @body(Cpu #cpu))
{
	(void)mutex.lock();
	defer (void)mutex.unlock();
	@body(#self._cpu);
}*/
//UnbufferedChannel{bool} gui_upd;
UnbufferedChannel{bool} gui_init;
Cpu cpu;


struct ThreadData
{
	Cpu* cpu;
	bool* running;
	UnbufferedChannel{bool} gui_init;
	bool* vsync_int;
}
// TODO: make all get instructions return a char[] so I can just do 'get_arg1()[:len] = get_arg2()[:len]' instead of all the bitmasks and switch statements and macros
// it will make memory to memory operations faster & I can have a reg->reg version as well
fn int main(String[] args)
{
	Cpu cpu;
	cpu.init();
	defer cpu.deinit();

	gui_init.init(mem)!!;
	defer (void)gui_init.destroy();
/*	gui_upd.init(mem)!!;
	defer (void)gui_upd.destroy();
	gui_done.init(mem)!!;
	defer (void)gui_done.destroy();*/

	bool running = true;
	bool vsync_int = false;
	Thread gui_thread;

	defer
	{
		running = false;
		(void)gui_thread.join();
	}
	if (catch gui_thread.create(&gui::run_gui, &&(ThreadData){&cpu, &running, gui_init, &vsync_int}))
	{
		logger::error("Failed to create gui thread!");
		return 1;
	}
	gui_init.pop()!!;

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


	cpu.mem_set(common::DEFAULT_INST_PTR, prog.len, prog)!!;

	logger::debug("Executing (%s b): %h", prog.len, prog[:prog.len < 200 ? prog.len : 200]);

	$if $feature(PERF):
		uint iterations = 0;
		Clock clock = clock::now();
	$endif

	Instruction inst;
//	while (running)
	{
		// TODO: maybe make each Cpu.inst_... a function in an associated value for an enum, so I could just do inst.execute()
		// it wouldn't work with the exit instructions tho... and might require multiple levels of switching/indexing so may not be faster
		switch (inst::GET_) @jump
		{
			case inst::NOP:
				logger::panic("Reached NOP (does not exist in fox32rom)");
				nextcase;
			case inst::GET:
				// set by the gui thread
				if (@unlikely(!running)) nextcase inst::BREAK;
				if (@unlikely(vsync_int))
				{
					vsync_int = false;
					cpu.throw(INT_VSYNC);
				}
				if (cpu.exception)
				{
					// cpu.interrupt(cpu.exception_type);
					cpu.error("got interrupt/exception %s (%s)", cpu.exception_type.name(), cpu.exception_type);
				}
				cpu.cycles ++;
				/*gui_upd.push(true)!!;
				if (!gui_done.pop()!!) nextcase inst::BREAK;*/
				if (cpu.cycles == max_cycles)
				{
					logger::info("Hit max_cycles of %s, exiting", max_cycles);
					nextcase inst::BREAK;
				}
				// TODO: set a clock speed
				$if $feature(DELAY):
					thread::sleep(((NanoDuration)1000).to_duration());
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
				logger::debug("Nearby mem: %s", cpu.mem_get(*cpu.inst_ptr, 10)!!);
				
				inst = (Instruction)cpu.mem_get(*cpu.inst_ptr, 2)!!.get(W16);

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
			case inst::IDIV:
				cpu.inst_idiv(inst);
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
			case inst::RCALL:
				cpu.inst_rcall(inst);
				nextcase inst::GET;
			case inst::RET:
				cpu.inst_ret(inst);
				nextcase inst::GET;
			case inst::ISE:
				cpu.inst_ise(inst);
				logger::error("Interrupts don't work yet :3");
				nextcase inst::GET;
			case inst::ICL:
				cpu.inst_icl(inst);
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
			case inst::SRL:
				cpu.inst_srl(inst);
				nextcase inst::GET;
			case inst::BTS:
				cpu.inst_bts(inst);
				nextcase inst::GET;
			case inst::BSE:
				cpu.inst_bse(inst);
				nextcase inst::GET;
			case inst::BCL:
				cpu.inst_bcl(inst);
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

fn fault Cpu.throw(&self, Interrupt exc)
{
	self.exception = true;
	self.exception_type = exc;
	return VM_EXCEPTION;
}

macro bool Cpu.should_execute(&self, Instruction inst)
{
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
		self.mem_set(*self.stack_ptr, $width, val)!;
	$else
		self.mem_get(*self.stack_ptr, $width)!.set($width, val);
	$endif
}

macro Cpu._pop(&self, BitWidth $width)
{
	var ret = self.mem_get(*self.stack_ptr, $width)!.get($width);
	*self.stack_ptr += $width;
	return ret;
}

macro Cpu.@setup_w(&self, Instruction inst, bool $move = true; @body(BitWidth $width, $Type, #src, #dst))
{
	@each_width(inst.width; BitWidth $width)
	{
		self.@setup(inst, $width, $move; #src, #dst)
		{
			@body($width, $width.type, #src, #dst);
		};
	};
}

// TODO: also return $Type = $width.type
macro Cpu.@setup(&self, Instruction inst, BitWidth $width, bool $move = true; @body(#src, #dst))
{
	String $inst_name = @inst_name();
	InstructionType $type = @inst_type();
	$if $feature(FOXLOG):
		self.print_instr(inst, $width, $type, $inst_name);
	$endif
	if (self.should_execute(inst))
	{
		(void)self.@args(inst, $inst_name, $type, $width; #src, #dst)
		{
			(void)@body(#src, #dst);
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

// TODO: have #src and #dst be both getters and setters, so you can do #dst.set(#src.get() + #dst.get()) (ofc storing #dst first)
// this would allow me to optimisze mem->mem movs so I won't need to contantly cast between char[] and uint.
// something like this:
/*
	<*
		@require $typeof(val) == Register* ||| ($typeof(val) == char[] && val.len == $width)
	*>
	macro Register.set(&self, BitWidth $width, val)
	{
		$if $typeof(val) == char[]:
			self = val.to_$width();
		$else
			self = val;
		$endif
	}
	macro Register.get(self, BitWidth $width, bool $signed = false)
*/
// and it would be the same for char[].set(), and then typeof(#src and #dst) could just be Register* or char[] and I won't need both get_value and set_value
// it could also result in increased performance if done correctly for mem->mem and reg->reg bc no char[]->int->char[] conversions or double bitmasking along the way
macro Cpu.@args(&self, Instruction inst, String $inst_name, InstructionType $type, BitWidth $width; @body(#src, #dst))
{
	$switch $type.arg_count():
		$case 0:
			@body(no_params($inst_name, SRC), @no_param($inst_name, DST));
		$case 1:
			// $typefrom($width.type) src = self.get_val($width, inst, SRC);
			// @body(src, no_param($type, DST));
			@body(self.get_val($width, inst, SRC)!, no_param($inst_name, DST));
		$case 2:
			$if $type.is_bit_op():
				// $typefrom($width.type) src = self.get_val(W8, inst, SRC);
				@body(self.get_val(W8, inst, SRC)!, self.get_val($width, inst, DST)!);
			$else
				// $typefrom($width.type) src = self.get_val($width, inst, SRC);
				@body(self.get_val($width, inst, SRC)!, self.get_val($width, inst, DST)!);
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
			char reg = self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8);
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
			char reg = self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8);
			uint smol_offset = !inst.has_offset ? 0 : self.mem_get(self.inst_ptr_next + offset + 1, 1)!.get(W8);
			self.mem_get(self.regs[reg] + smol_offset, $width)!.set($width, val);
			// self.mem_get(self.regs[self.mem_get(self.inst_ptr_next + offset, 1).get(W8)], $width).set($width, val);
		case IMM:
			self.error("mov into immediate value not implemented");
		case IMM_PTR:
			self.mem_get(self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE)!.get(W32), $width)!.set($width, val);
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
			logger::debug("Reading from register %s", common::REG_NAMES[self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8)]);
			return self.regs[self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8)].read($width);
		case REG_PTR:
			char reg = self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8);
			uint smol_offset = !inst.has_offset ? 0 : self.mem_get(self.inst_ptr_next + offset + 1, 1)!.get(W8);
			$typefrom($width.type) val = self.mem_get(self.regs[reg] + smol_offset, $width)!.get($width);
			return val;// self.mem_get(self.regs[reg] + self.mem_get(self.inst_ptr_next + 1, 1).get(W8), $width).get($width);
		case IMM:
			return self.mem_get(self.inst_ptr_next + offset, $width)!.get($width);
		case IMM_PTR:
			return self.mem_get(self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE)!.get(W32), $width)!.get($width);
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
