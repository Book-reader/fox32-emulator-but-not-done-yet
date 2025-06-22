module disk;
import emulator;
import common;
import logger;
import std::io;

faultdef TOO_MANY_DISKS,
			INVALID_DISK_ID,
			DISK_NOT_MOUNTED;

const MAX_DISKS = 4;
const SECTOR_SIZE = 512;

struct Disk
{
	File file;
	usz size;
	bool mounted;
}

Disk[MAX_DISKS] disks;
Word buffer_addr;

fn void? insert(String disk_file, usz disk_id)
{
	File file = file::open(disk_file, "rb+")!;
	// TODO: add size method to file in stdlib, or atleast file::size(File)
	disks[disk_id] = {file, file::get_size(disk_file)!, true};
	// logger::info("inserted disk filename %s id %s of size %s (0x%.8x)", disk_file, disk_id, disks[disk_id].size, disks[disk_id].size);
}

fn void? remove(usz disk_id)
{
	if (disk_id > MAX_DISKS) return INVALID_DISK_ID?;
	if (disks[disk_id].mounted) (void)disks[disk_id].file.close();
	disks[disk_id] = {};
}

fn Word size(usz disk_id) @inline => (Word)disks[disk_id].size;

fn Word buffer() @inline => buffer_addr;

fn void set_buffer(Word addr) @inline => buffer_addr = addr;


// TODO: ask for or PR an offset param for native_f(read|write)
// nvm it looks like file.seek removes that need
// import libc;

fn void? read(Cpu* cpu, usz disk_id, usz sector)
{
	if (!disks[disk_id].mounted) return;
	File* file = &disks[disk_id].file;
	Byte[SECTOR_SIZE] data;
	// libc::fread(&data, sector * SECTOR_SIZE, data.len, file.file);
	// TODO: the reference emulator doesn't actually exit on error
	file.seek(sector * SECTOR_SIZE)!;
	file.read((char[])&data)!;
	// logger::info("Read data from sector %s idx %s (0x%.8x): %s", sector, sector * SECTOR_SIZE, sector * SECTOR_SIZE, data);
	// TODO: maybe the problem is actually that there is an off-by-one with the buffer address?
	cpu.mem_set(buffer_addr, SECTOR_SIZE, &data)!;
	// logger::info("Data at the buffer_addr (0x%.8x): %s", buffer_addr, cpu.mem_get(buffer_addr, SECTOR_SIZE)!);
}

fn void? write(Cpu* cpu, usz disk_id, usz sector)
{
	// logger::info("writing sector %s of disk %s", sector, disk_id);
	if (!disks[disk_id].mounted)
	{
		// logger::info("disk %s is not mounted so cannot be written to", disk_id);
		return;
	}
	File* file = &disks[disk_id].file;
	//char[] data = cpu.mem_get(buffer_addr, SECTOR_SIZE)!;
	file.seek(sector * SECTOR_SIZE)!;
	file.write((char[])cpu.mem_get(buffer_addr, SECTOR_SIZE)!)!;
	// logger::info("Wrote data into sector %s idx %s (0x%.8x): %s", sector, sector * SECTOR_SIZE, sector * SECTOR_SIZE, cpu.mem_get(buffer_addr, SECTOR_SIZE)!);
	// libc::fwrite(data.ptr, sector * SECTOR_SIZE, data.len, file.file);
}
