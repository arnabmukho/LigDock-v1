import sys
from Bio.PDB import PDBParser, Selection

def calculate_center_of_mass(residues):
    total_mass = 0.0
    center_of_mass = [0.0, 0.0, 0.0]
    for residue in residues:
        for atom in residue:
            mass = atom.mass if hasattr(atom, 'mass') else 1.0  # Use a default mass of 1.0 if not available
            total_mass += mass
            center_of_mass[0] += atom.coord[0] * mass
            center_of_mass[1] += atom.coord[1] * mass
            center_of_mass[2] += atom.coord[2] * mass
    center_of_mass[0] /= total_mass
    center_of_mass[1] /= total_mass
    center_of_mass[2] /= total_mass
    return center_of_mass

def get_binding_site_coordinates(protein_file, residue_ids):
    parser = PDBParser()
    structure = parser.get_structure('protein', protein_file)
    model = structure[0]
    chain = model['A']  # Assuming chain A, modify if necessary

    residues = [chain[rid] for rid in residue_ids]
    center_of_mass = calculate_center_of_mass(residues)
    return center_of_mass

if __name__ == "__main__":
    protein_file = sys.argv[1]
    residue_ids = [int(rid) for rid in sys.argv[2].split(',')]
    center_of_mass = get_binding_site_coordinates(protein_file, residue_ids)
    print(f"{center_of_mass[0]} {center_of_mass[1]} {center_of_mass[2]}")
