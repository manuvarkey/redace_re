"""Rebuild detailed Britain assets using the running Blender MCP addon (port 9876)."""
import subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent
for script in ['britain_textures.py','run_blender_mcp.py','configure_britain.py']:
 args=[sys.executable,str(ROOT/script)]
 if script=='run_blender_mcp.py':args.append(str(ROOT/'blender_britain.py'))
 subprocess.run(args,check=True)
