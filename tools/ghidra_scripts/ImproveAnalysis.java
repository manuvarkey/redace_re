// Second pass for RedAce.exe:
//  1. Create functions at .text targets of pointers found in .rdata/.data (COM vtables, callbacks).
//  2. Create functions at remaining undefined code after function ends (gap filling).
//  3. Rename FUN_xxxx functions that reference exactly one "d:/dive5dev/..." source path string
//     to <module>_<address>, and add a plate comment with every source path referenced.
// @category Analysis
import java.util.*;

import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.data.StringDataInstance;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.symbol.*;

public class ImproveAnalysis extends GhidraScript {
	private MemoryBlock text;

	@Override
	public void run() throws Exception {
		Memory mem = currentProgram.getMemory();
		text = mem.getBlock(".text");
		int before = currentProgram.getFunctionManager().getFunctionCount();

		int fromPtr = 0;
		for (String name : new String[] { ".rdata", ".data" }) {
			MemoryBlock b = mem.getBlock(name);
			if (b == null || !b.isInitialized()) {
				continue;
			}
			for (Address a = b.getStart(); a.compareTo(b.getEnd().subtract(3)) < 0; a = a.add(4)) {
				monitor.checkCancelled();
				long v = mem.getInt(a) & 0xffffffffL;
				Address t = toAddr(v);
				if (looksLikeEntry(t) && makeFunction(t)) {
					fromPtr++;
				}
			}
		}
		println("functions from pointer tables: " + fromPtr);

		int fromGaps = 0;
		boolean changed = true;
		while (changed) {
			changed = false;
			for (Function f : currentProgram.getFunctionManager().getFunctions(text.getStart(), true)) {
				monitor.checkCancelled();
				Address next = f.getBody().getMaxAddress().add(1);
				// skip int3/nop padding between functions
				while (text.contains(next)) {
					byte c = mem.getByte(next);
					if (c != (byte) 0xcc && c != (byte) 0x90) {
						break;
					}
					next = next.add(1);
				}
				if (looksLikeEntry(next) && makeFunction(next)) {
					fromGaps++;
					changed = true;
				}
			}
		}
		println("functions from gaps: " + fromGaps);

		int renamed = 0;
		ReferenceManager rm = currentProgram.getReferenceManager();
		Listing listing = currentProgram.getListing();
		for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
			monitor.checkCancelled();
			TreeSet<String> paths = new TreeSet<>();
			for (Address src : f.getBody().getAddresses(true)) {
				for (Reference r : rm.getReferencesFrom(src)) {
					Data d = listing.getDataAt(r.getToAddress());
					if (d == null || !d.hasStringValue()) {
						continue;
					}
					String s = StringDataInstance.getStringDataInstance(d).getStringValue();
					if (s != null && s.startsWith("d:/dive5dev/")) {
						paths.add(s.substring("d:/dive5dev/src/".length()));
					}
				}
			}
			if (paths.isEmpty()) {
				continue;
			}
			f.setComment("Dive5 source references:\n  " + String.join("\n  ", paths));
			if (paths.size() == 1 && f.getName().startsWith("FUN_")) {
				String p = paths.first();
				String mod = p.substring(p.lastIndexOf('/') + 1).replaceAll("\\.[^.]*$", "");
				f.setName(mod + "_" + f.getEntryPoint(), SourceType.ANALYSIS);
				renamed++;
			}
		}
		println("renamed from source paths: " + renamed);
		println("function count " + before + " -> " +
			currentProgram.getFunctionManager().getFunctionCount());
	}

	private boolean looksLikeEntry(Address t) throws Exception {
		if (t == null || text == null || !text.contains(t)) {
			return false;
		}
		Listing listing = currentProgram.getListing();
		if (listing.getFunctionContaining(t) != null) {
			return false;
		}
		Instruction ins = listing.getInstructionContaining(t);
		if (ins != null && !ins.getAddress().equals(t)) {
			return false;
		}
		Data d = listing.getDefinedDataContaining(t);
		return d == null;
	}

	private boolean makeFunction(Address t) {
		if (getInstructionAt(t) == null) {
			DisassembleCommand dis = new DisassembleCommand(t, null, true);
			if (!dis.applyTo(currentProgram, monitor) || getInstructionAt(t) == null) {
				return false;
			}
		}
		CreateFunctionCmd cmd = new CreateFunctionCmd(t);
		return cmd.applyTo(currentProgram, monitor);
	}
}
