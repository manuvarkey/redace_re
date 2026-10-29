// Label every copy of each Dive5 GUID (from decomp/dive5_guids.tsv) with its IID_/CLSID_/CATID_ name
// and type it as GUID, so decompiled code shows e.g. &IID_IDiCDAudio instead of &DAT_xxxx.
// Usage: -postScript ApplyGuids.java <path-to-dive5_guids.tsv>
// @category Analysis
import java.io.*;
import java.util.*;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.data.*;
import ghidra.program.model.listing.Data;
import ghidra.program.model.symbol.SourceType;

public class ApplyGuids extends GhidraScript {
	@Override
	public void run() throws Exception {
		File tsv = new File(getScriptArgs()[0]);
		DataType guidType = findGuidType();
		int labels = 0;
		try (BufferedReader r = new BufferedReader(new FileReader(tsv))) {
			r.readLine();
			String line;
			while ((line = r.readLine()) != null) {
				String[] f = line.split("\t");
				String name = f[1].trim().replace(' ', '_');
				byte[] bytes = guidBytes(f[3]);
				Address a = currentProgram.getMinAddress();
				while ((a = find(a, bytes)) != null) {
					monitor.checkCancelled();
					clearListing(a, a.add(15));
					Data d = createData(a, guidType);
					if (d != null) {
						createLabel(a, name, false, SourceType.IMPORTED);
						labels++;
					}
					a = a.add(1);
				}
			}
		}
		println("GUID labels applied: " + labels);
	}

	private DataType findGuidType() {
		List<DataType> out = new ArrayList<>();
		currentProgram.getDataTypeManager().findDataTypes("GUID", out);
		for (DataType t : out) {
			if (t.getLength() == 16) {
				return t;
			}
		}
		return new ArrayDataType(ByteDataType.dataType, 16, 1);
	}

	// GUID string AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE to its little-endian in-memory layout
	private static byte[] guidBytes(String g) {
		String h = g.replace("-", "");
		byte[] b = new byte[16];
		int[] order = { 3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15 };
		for (int i = 0; i < 16; i++) {
			b[i] = (byte) Integer.parseInt(h.substring(order[i] * 2, order[i] * 2 + 2), 16);
		}
		return b;
	}
}
