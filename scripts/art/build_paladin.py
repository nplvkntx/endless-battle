"""Rebuild Paladin visuals using the existing source rig and animation actions."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('remodel_paladin.py')), run_name='__main__')
