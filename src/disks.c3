module disk;
import emulator;

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
usz num_disks;
uint buffer_addr;

fn void? insert(String disk_file, usz disk_id)
{
	if (num_disks == MAX_DISKS) return TOO_MANY_DISKS?;
	File file = file::open(disk_file, "rb")!;
	// TODO: add size method to file in stdlib, or atleast file::size(File)
	disks[disk_id] = {file, file::get_size(disk_file)!, true};
}

fn void? remove(usz disk_id)
{
	if (disk_id > MAX_DISKS) return INVALID_DISK_ID?;
	(void)disks[disk_id].file.close();
	disks[disk_id] = {};
}

fn usz size(usz disk_id) => disks[disk_id].size;

fn void? read(Cpu* cpu, usz disk_id, usz sector)
{
	File* file = &disks[disk_id].file;
	file.seek(sector * SECTOR_SIZE)!;
	char[SECTOR_SIZE] data;
	file.read(&data)!;
	cpu.mem_set(buffer_addr, SECTOR_SIZE, &data)!;
}

fn void? write(Cpu* cpu, usz disk_id, usz sector)
{
	File* file = &disks[disk_id].file;
	file.seek(sector * SECTOR_SIZE)!;
	file.write(cpu.mem_get(buffer_addr, SECTOR_SIZE)!)!;
}
