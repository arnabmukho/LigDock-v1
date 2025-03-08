# LigDock v1

LigDock v1 is a pipeline for running AutoDock Vina to perform docking simulations. The pipeline includes scripts to prepare the protein and ligands, run the docking simulations, and generate the final docked poses with both the protein and ligand included.

## Table of Contents

- [Requirements](#requirements)
- [Cloning the Repository](#cloning-the-repository)
- [Usage](#usage)
- [Running the Docking Pipeline](#running-the-docking-pipeline)
- [Steps in the Docking Pipeline](#steps-in-the-docking-pipeline)

## Requirements

- AutoDock Vina
- MGLTools
- Open Babel
- UCSF Chimera
- Python 3.x
- Biopython

## Cloning the Repository

You can clone the repository from GitHub using the following command:

```bash
git clone https://github.com/arnabmukho/LigDock-v1.git
```

## Usage

### Running the Docking Pipeline

1. Place your protein file (e.g., `protein.pdb`) in the same directory as the script.
2. Create a directory named `ligands` and place individual ligand SDF files in that directory.
3. Run the docking script:
   ```bash
   ./LigDock.sh
   ```

## Steps in the Docking Pipeline

1. **Prepare the Protein:**
   - The protein structure is cleaned by removing specified heteroatoms.
   - Hydrogens are added, and energy minimization is performed using UCSF Chimera.
   - The minimized protein structure is prepared for docking using MGLTools.

2. **Prepare the Ligands:**
   - Each ligand in SDF format is converted to PDBQT format using Open Babel.
   - Hydrogens and Gasteiger charges are added to the ligand.
   - The ligand is prepared for docking using MGLTools.

3. **Run Docking Simulations:**
   - Binding site coordinates are extracted using a Python script.
   - AutoDock Vina is used to perform docking simulations for each ligand.
   - The protein and docked ligand are combined into a single PDBQT file.

4. **Output:**
   - Docked poses are saved in the `docked_poses` directory.
   - Log files are saved in the `logs` directory.
   - A summary log file is generated with the docking scores.
