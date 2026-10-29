// Headless export: full C/C++ decompilation (CppExporter) plus a function index.
// @category Export
import java.io.File;
import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.app.util.exporter.CppExporter;
import ghidra.program.model.listing.Function;

public class ExportAll extends GhidraScript {
	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		File outDir = new File(args.length > 0 ? args[0] : "decomp");
		outDir.mkdirs();

		try (PrintWriter idx = new PrintWriter(new File(outDir, "functions.tsv"))) {
			idx.println("address\tname\tsize\tcalling_convention\tsignature");
			for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
				idx.printf("%s\t%s\t%d\t%s\t%s%n", f.getEntryPoint(), f.getName(true),
					f.getBody().getNumAddresses(), f.getCallingConventionName(),
					f.getSignature().getPrototypeString());
			}
		}

		CppExporter exporter = new CppExporter();
		java.util.List<ghidra.app.util.Option> opts = exporter.getOptions(() -> currentProgram);
		for (ghidra.app.util.Option o : opts) {
			if (o.getName().equals(CppExporter.CREATE_HEADER_FILE)) {
				o.setValue(Boolean.TRUE);
			}
		}
		exporter.setOptions(opts);
		exporter.export(new File(outDir, "RedAce.c"), currentProgram, null, monitor);
		println("Exported to " + outDir.getAbsolutePath());
	}
}
