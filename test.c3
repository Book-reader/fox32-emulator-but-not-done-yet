module test1;
/*
enum Size : char (inline usz byte_size)
{
	BYTE = 1,
	HALF = 2,
	WORD = 4,
}

// temp due to compiler bug
typedef Register = uint;
typedef Word = inline uint;
typedef Half = inline ushort;
typedef Byte = inline char;
/*alias Register = uint;
alias Word = uint;
alias Half = ushort;
alias Byte = char;*/


macro is_vm_int_type($Type) => $Type.typeid == Word.typeid ||| $Type.typeid == Half.typeid ||| $Type.typeid == Byte.typeid;
macro is_vm_mem_type($Type) => $Type.typeid == MemoryWord.typeid ||| $Type.typeid == MemoryHalf.typeid ||| $Type.typeid == MemoryByte.typeid ||| $Type.typeid == Memory.typeid;
macro is_vm_type($Type) => is_vm_int_type($Type) ||| is_vm_mem_type($Type);
macro @is_vm_val(#val) => is_vm_type($typeof(#val));
macro @is_vm_int(#val) => is_vm_int_type($typeof(#val));
macro @is_vm_mem(#val) => is_vm_mem_type($typeof(#val));
macro @is_vm_arg(#val) => @is_vm_mem(#val) ||| @is_vm_reg(#val);
macro @is_vm_reg(#val) => @typeis(#val, Register);
macro @is_vm_int_ptr(#val) => $defined(*#val) &&& is_vm_int(#val);
macro @inner(#val) => $typeof(#val).inner;
typedef Memory = Byte[];
macro Memory.set(self, val, Size $size = WORD) => bytes_set(self, $size, val);


typedef MemoryWord = Byte[Word.sizeof]*;
typedef MemoryHalf = Byte[Half.sizeof]*;
typedef MemoryByte = Byte[Byte.sizeof]*;

macro usz MemoryWord.len(#self) @safemacro @const @operator(len) => Word.sizeof;
macro usz MemoryHalf.len(#self) @safemacro @const @operator(len) => Half.sizeof;
macro usz MemoryByte.len(#self) @safemacro @const @operator(len) => Byte.sizeof;

// fn Byte MemoryWord.get_idx(self, usz idx) @operator([]) @inline => (*($typefrom(@inner(self)))self)[idx];
// fn Byte MemoryHalf.get_idx(self, usz idx) @operator([]) @inline => (*($typefrom(@inner(self)))self)[idx];
// fn Byte MemoryByte.get_idx(self, usz idx) @operator([]) @inline => (*($typefrom(@inner(self)))self)[idx];

macro MemoryWord.get(self, Size $size = WORD) => bytes_get(self, $size);
macro MemoryHalf.get(self, Size $size = HALF) => bytes_get(self, $size);
macro MemoryByte.get(self, Size $size = BYTE) => bytes_get(self, $size);

macro MemoryWord.set(self, val, Size $size = WORD) => bytes_set(self, $size, val);
macro MemoryHalf.set(self, val, Size $size = HALF) => bytes_set(self, $size, val);
macro MemoryByte.set(self, val, Size $size = BYTE) => bytes_set(self, $size, val);


<*
 this isn't a hack it totally isn't a hack how dare you call it a hack
 @require @is_vm_mem(self)
*>
macro bytes_get(self, Size $size)
{
	$if $size <= self.len():
		var val = (char[self.len()]*)self;
	$else
		char[$size] val;
		val[:self.len()] = (*(char[self.len()]*)self)[:self.len()];
	$endif
	$switch $size:
	$case BYTE:
		return (Byte)(*val)[0];
	$case HALF:
		return (Half)bitorder::read(val, UShortLE);
	$case WORD:
		return (Word)bitorder::read(val, UIntLE);
	$endswitch
}

<*
 @require @is_vm_mem(self)
 @require @is_vm_arg(val)
*>
macro bytes_set(self, Size $size, val)
{
	$if @is_vm_mem(val):
		((Byte[])self)[:$size] = ((Byte[])val)[:$size];
	$else
		$error "a";
	$endif
/*	$if $is_const(self.len()):
		Byte[] dst = (Byte[self.len()]*)self;
	$else
		Byte[] dst = self;
	$endif
	$switch $size:
	$case BYTE:
		self[self.len()] = val;
	$case HALF:
		self[]
	$case WORD:
	$endswitch*/
}


macro Size @width_of(#val) @const
{
	$switch $typeof(#val):
	$case Byte:
	$case MemoryByte:
		return BYTE;
	$case Half:
	$case MemoryHalf:
		return HALF;
	$case Word:
	$case MemoryWord:
		return WORD;
	$default:
		$error $typeof(val).nameof +++ ` is not a valid type to get the width of`;
	$endswitch
}

macro Register.get(self, Size $size = WORD)
{
	$switch $size:
	$case BYTE:
		return (Byte)(self & 0x000000ff);
	$case HALF:
		return (Half)(self & 0x0000ffff);
	$case WORD:
		return (Word)self;
	$endswitch
}

<*
 @require @is_vm_val(val) : `the type of "val" must be a vm int or array`
 @require $defined(Size.$eval($stringify(#size))) ||| @typeis(#size, Size) ||| @is_empty_macro_slot(#size)
*>
macro Register.set(&self, val, #size = EMPTY_MACRO_SLOT) @safemacro
{
	Size $size; // = @select(!$defined(Size.$eval($stringify(#size))) ||| @is_empty_macro_slot(#size), @size_of(val), #size);
	$switch:
	$case $defined(Size.$eval($stringify(#size))):
	$case @typeis(#size, Size):
		$size = #size;
	$case @is_empty_macro_slot(#size):
		$size = @width_of(val);
	$default:
		$error "Invalid type for #size: " +++ $typeof(#size).nameof;
	$endswitch

	bool $is_int = @is_vm_int(val);
	$if $is_int:
		$switch $size:
		$case BYTE:
			*self = (*self & ~0x000000ff) | (Register)val;
		$case HALF:
			*self = (*self & ~0x0000ffff) | (Register)val;
		$case WORD:
			*self = (Register)val;
		$endswitch
	$else
		$assert @is_vm_mem(val);
		self.set(val.get($size));
	$endif
}

import std::io;
import std::time;
fn int main(String[] args)
{
	
	Register r = 0xffffffff;
	io::printfn("%.8x", (uint)r);
	r.set((Byte)1);
	io::printfn("%.8x", (uint)r);
	r.set((Word)0x30000000);
	io::printfn("%.8x", (uint)r);
	r.set((Half)2);
	io::printfn("%.8x", (uint)r);

	// MemoryWord x = (MemoryWord)&&(Byte[*]){0xff, 0xff, 0x00, 0x00};
	MemoryHalf x = (MemoryHalf)&&(Byte[*]){0xff, 0xaa};
	io::printfn("%.8x", x.get(BYTE));

	r.set(x);
	io::printfn("%.8x", (uint)r);

	MemoryWord y = (MemoryWord)&&(Byte[*]){0x00, 0x00, 0x00, 0x00};
	y.set(x, BYTE);
	io::printfn("%.8x", y.get(WORD));

	Clock c;
	NanoDuration time;
	const usz ITER = 100000000;

	Byte[4] a1 = {0x00, 0x00, 0x00, 0x00};
	Byte[2] b1 = {0xff, 0xaa};
	Byte[4] a2 = {0x00, 0x00, 0x00, 0x00};
	Byte[2] b2 = {0xff, 0xaa};
	Byte[4] a3 = {0x00, 0x00, 0x00, 0x00};
	Byte[2] b3 = {0xff, 0xaa};
	for (usz j = 0; j < 10; j++)
	{
		@volatile_store(c, clock::now());
		for (usz i = 0; i < @volatile_load(ITER); i++)
		{
			MemoryWord a;//  = (MemoryWord)&a1;
			@volatile_store(a, (MemoryWord)&&(Byte[*]){0x00, 0x00, 0x00, 0x00});
			// @volatile_store(a, (MemoryWord)&a1);
			MemoryHalf b;// = (MemoryHalf)&b1;
			@volatile_store(b, (MemoryHalf)&&(Byte[*]){0xff, 0xaa});
			// @volatile_store(b, (MemoryHalf)&b1);
			// ((Byte[])a)[:2] = ((Byte[])b)[:2];
			//io::printn((Byte[])a);
			a.set(b, HALF);
			@volatile_load(a);
		}
		time = c.mark();
		io::printfn("new method 1 took %s", time);

		@volatile_store(c, clock::now());
		for (usz i = 0; i < @volatile_load(ITER); i++)
		{
			Memory a;// = (Memory)&a2;
			@volatile_store(a, (Memory){0x00, 0x00, 0x00, 0x00});
			Memory b;// = (Memory)&b2;
			@volatile_store(b, (Memory){0xff, 0xaa});
			// ((Byte[])a)[:2] = ((Byte[])b)[:2];
			a.set(b, HALF);
			@volatile_load(a);
		}
		time = c.mark();
		io::printfn("new method 2 took %s", time);

		@volatile_store(c, clock::now());
		for (usz i = 0; i < @volatile_load(ITER); i++)
		{
			char[] a;// = (char[])&a3;
			@volatile_store(a, (char[]){0x00, 0x00, 0x00, 0x00});
			char[] b;// = (char[])&b3;
			@volatile_store(b, (char[]){0xff, 0xaa});
			a.set(HALF, b.get(HALF));
			@volatile_load(a);
		}
		time = c.mark();
		io::printfn("old method   took %s", time);
	}

	// MemoryWord x = (MemoryWord)"abcd";
	// io::printfn("%c", (char)x[0]);
	return 0;
}


<*
 @require values::@is_int(val) && !$defined(*val)
*>
macro void char[].set(self, Size $width, val) => self[:$width] = ((char*)&val)[:$width];

<*
	this doesn't work due to compiler missing feature:
	@ensure $typeof(return).typeid == $width.type
*>
macro char[].get(self, Size $width)
{
  $switch $width:
    $case BYTE:
      return (char)self[0];
	$case HALF:
		return (ushort)bitorder::read(self, UShortLE);
	$case WORD:
		return (uint)bitorder::read(self, UIntLE);
  $endswitch
}
*/

enum Size : char (inline usz byte_size)
{
	BYTE = 1,
	HALF = 2,
	WORD = 4,
}

typedef Register = uint;
typedef Word = inline uint;
typedef Half = inline ushort;
typedef Byte = inline char;
typedef MemoryWord = Byte[Word.sizeof]*;
typedef MemoryHalf = Byte[Half.sizeof]*;
typedef MemoryByte = Byte[Byte.sizeof]*;

macro Word Word.add_h(self, Half other) @operator_s(+) => self + (Word)other;
macro Word Word.add_b(self, Byte other) @operator_s(+) => self + (Word)other;

macro slice_to_num(char[] val, Size $size)
{
	$switch $size:
	$case BYTE:
		return (Byte)val[0];
	$case HALF:
		return (Half)bitorder::read(val, UShortLE);
	$case WORD:
		return (Word)bitorder::read(val, UIntLE);
	$endswitch
}

alias Memory = Byte[];
/*macro Memory.get(self, Word start, #len) @safemacro
{
	Word $len;
	$switch:
	$case !$defined(#len) &&& $defined(Size.$eval($stringify(#len))):
	$case @typeis(#len, Size):
		Size $s = #len;
		$len = $s.byte_size;
	$case @typeis(#len, Word):
		$len = #len;
	$default:
		$error `"%s" is an invalid type for Memory.get, must be "Word" or "Size"`, $typeof(#len).nameof;
	$endswitch
	$echo $len;

	
}*/

/*fn void? Cpu.inst_mov(&self, Instruction inst) => @setup_w2(inst; Size $size, #src, #dst)
{
	#dst.set(#src);
}*/

// I should try to figure out a way to automatically detect if a src or dst would be an exception without having to make all instructions optional and use "!" everywhere
// Maybe automatically fetching the values before passing them would be worth it for the minor performance loss on (interrupting that though, no, because sometimes the conditional evaluation prevents a page fault)

// #src and #dst should be some sort of constant thing that ideally has no data (not struct, maybe macro) that I can call get(SRC/DST) and set(SRC/DST, val, size?) methods on & it knows the size & type automatically
// this may be difficult without storing any data at all, but I'll see what I can do

/*fn void Cpu.inst_add(&self, Instruction inst) => @setup_w2(inst; Size $size, $Type, #src, #dst)
{
	$Type res @noinit;
	self.flags.carry = math::overflow_add(#dst, #src, &res);
	self.flags.zero = res == 0;
	self.set(DST, res);
}*/

enum ArgPos : Byte (inline String name)
{
	SRC = "src",
	DST = "dst",
}
enum ArgType : char (String fox32name)
{
	REG = "REG   ",
	REG_PTR = "REGPTR",
	IMM = "IMM   ",
	IMM_PTR = "IMMPTR",
}
typedef InstructionType = char;

struct Cpu
{
	Memory ram;
	Word inst_ptr_next;
	Register[10] regs;
}
macro Byte[] Cpu.mem_get(&self, ...) => {0, 0, 0, 0};
macro Byte @arg_offset(...) => 0;
macro Byte[].get(self, ...) => unreachable();

macro Register.get_new(self, Size $size)
{
	$switch $size:// this might actually be more performant? idk
	$case BYTE:
		return (Byte)self;// (self & 0x000000ff);
	$case HALF:
		return (Half)self;//(self & 0x0000ffff);
	$case WORD:
		return (Word)self;
	$endswitch
}

macro Register.get_old(self, Size $size)
{
	$switch $size:
	$case BYTE:
		return (Byte)(self & 0x000000ff);
	$case HALF:
		return (Half)(self & 0x0000ffff);
	$case WORD:
		return (Word)self;
	$endswitch
}


bitstruct Instruction (Printable) : $typefrom(Half.inner) @littleendian
{
	ArgType src : 0..1;
	ArgType dst : 2..3;
	Byte cond : 4..6;
	bool has_offset : 7;
	InstructionType type : 8..13;
	Size size : 14..15;
}

import value_hack;

// TODO: report bug
// alias test = value_hack::test{ArgPos.SRC, Size.HALF, 0};
// alias TEST = value_hack::TEST{ArgPos.SRC, Size.HALF, 0};
import std::io;
import std;
// TODO: check if using @body(src, dst) impacts performance over @body(#src, #dst)
fn int main(String[] args) => @pool()
{
	Memory ram = mem::temp_array(Byte, 1000);
	Size $s = HALF;
	InstructionType $inst = 0;
	Cpu cpu;
	Instruction inst;
	Hack{ArgPos.SRC, Size.HALF, $inst} x = value_hack::from{ArgPos.SRC, Size.HALF, $inst}(&cpu, inst);
	// x.get(); // equivalent to cpu.get_val($width, inst, DST, $inst);
	// x.set(1); // equivalent to cpu.set_val($width, inst, DST, 1, $inst);
	// ram.get(0, $s);
	// ram.get(0, WORD);
	// ram.get(0, (Word)123);

	Clock c;
	NanoDuration time;
	usz b;
	const usz ITER = 100000000;
	for (usz j = 0; j < 10; j++)
	{
		@volatile_store(c, clock::now());
		b = 0;
		for (usz i = 0; i < @volatile_load(ITER); i++)
		{
			Register a = 0xaabbccdd;
			@volatile_store(b, b + (usz)a.get_new(HALF));
		}
		time = c.mark();
		io::printfn("new method took %s with result %s", time, b);

		@volatile_store(c, clock::now());
		b = 0;
		for (usz i = 0; i < @volatile_load(ITER); i++)
		{
			Register a = 0xaabbccdd;
			@volatile_store(b, b + (usz)a.get_old(HALF));
		}
		time = c.mark();
		io::printfn("old method took %s with resul %s", time, b);
	}
	return 0;
}
// 
<*
 :)
 @require $typeof(ARG_POS).typeid == ArgPos.typeid
 @require $typeof(WIDTH).typeid == Size.typeid
 @require $typeof(INSTRUCTION).typeid == InstructionType.typeid
*>
module value_hack {ARG_POS, WIDTH, INSTRUCTION};
import test1;

typedef Hack = Cpu*;
Instruction inst;

macro Hack from(Cpu* cpu, Instruction inst_)
{
	inst = inst_;
	return (Hack)cpu;
}

macro Cpu* @c(#self) @private => (Cpu*)#self;

macro Hack.get(#self, Size $size = WIDTH) @safemacro
{
	Cpu* c = @c(#self);
	Byte offset = test1::@arg_offset($width, inst, $inst_type, $arg);
	Word inst_ptr = c.inst_ptr_next + offset;
	// return test1::slice_to_num((char[])@c(#self).ram[], WIDTH);
	switch (inst.$eval(ARG_POS.name))
	{
		case REG:
			return c.regs[c.mem_get(inst_ptr, BYTE).get(BYTE)!].get(WIDTH);
		case REG_PTR:
			Byte reg = c.mem_get(inst_ptr, BYTE).get(BYTE)!;
			Byte smol_offset = inst.has_offset ? c.mem_get(inst_ptr + 1, BYTE).get(BYTE)! : 0;
			return c.mem_get(c.regs[reg] + smol_offset, WIDTH).get(WIDTH)!;

	}
/*
	uint offset = @arg_offset($width, inst, $inst_type, $arg);
	// logger::debug("Current idx is %s, calculated offset is %s", self.inst_ptr_next, offset);
	switch (inst.$eval(ARG_POS.name))
	{
		case REG:
			return self.regs[self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8)].read($width);
		case REG_PTR:
			char reg = self.mem_get(self.inst_ptr_next + offset, 1)!.get(W8);
			uint smol_offset = !inst.has_offset ? 0 : self.mem_get(self.inst_ptr_next + offset + 1, 1)!.get(W8);
			return self.mem_get(self.regs[reg] + smol_offset, $width)!.get($width);
		case IMM:
			return self.mem_get(self.inst_ptr_next + offset, $width)!.get($width);
		case IMM_PTR:
			return self.mem_get(self.mem_get(self.inst_ptr_next + offset, common::PTR_SIZE)!.get(W32), $width)!.get($width);
	}*/

}

macro Hack.set(#self, #val, Size $width = WIDTH) @safemacro
{

}

