#!/bin/bash

# Define variables
SCRIPT_DIR=$(dirname "$0")
PROTEIN="$SCRIPT_DIR/protein.pdb"  # Change to your protein file
LIGAND_DIR="$SCRIPT_DIR/ligands"  # Directory containing individual ligand SDF files
OUTPUT_DIR="$SCRIPT_DIR/docked_poses"  # Directory to save docked poses
LOG_DIR="$SCRIPT_DIR/logs"  # Directory to save log files
CONFIG_FILE="$SCRIPT_DIR/config.txt"  # Vina configuration file
SUMMARY_LOG="$SCRIPT_DIR/summary_log.txt"  # Summary log file
ERROR_LOG="$SCRIPT_DIR/error_log.txt"  # Error log file
VENV_DIR="$HOME/myenv"  # Path to the virtual environment

# Ensure MGLTools PATH
export PATH=$PATH:$HOME/MGLTools-1.5.6/bin

# Create output and log directories if they do not exist
mkdir -p $OUTPUT_DIR
mkdir -p $LOG_DIR

# Initialize the summary and error log files
echo "Ligand,Score" > $SUMMARY_LOG
echo "Ligand,Error" > $ERROR_LOG

# Prompt user to specify binding site residues
echo "Please specify the binding site residues (e.g., 123,456,789):"
read RESIDUES

# Prompt user to specify heteroatoms to remove
echo "Please specify the heteroatoms to remove (e.g., HOH,SO4):"
read HETEROATOMS

# Function to extract binding site coordinates using Python script
get_binding_site_coordinates() {
    # Activate the virtual environment and run the Python script
    source $VENV_DIR/bin/activate
    python3 "$SCRIPT_DIR/get_binding_site_coordinates.py" "$PROTEIN" "$RESIDUES"
    deactivate
}

# Function to remove specified heteroatoms from the protein structure
remove_heteroatoms() {
    local protein_pdb=$1
    local heteroatoms=$2
    local cleaned_protein_pdb="${protein_pdb%.pdb}_cleaned.pdb"
    grep -vE "HETATM.*($heteroatoms)" "$protein_pdb" > "$cleaned_protein_pdb"
    echo "$cleaned_protein_pdb"
}

# Function to prepare protein using Chimera
prepare_protein() {
    local protein_pdb=$1
    local output_pdbqt=$2
    local minimized_protein_pdb="${protein_pdb%.pdb}_minimized.pdb"

    # Use Chimera for adding hydrogens and energy minimization
    chimera --nogui << EOF
open $protein_pdb
delete solvent
addh
minimize
write format pdb 0 $minimized_protein_pdb
EOF

    if [ ! -f "$minimized_protein_pdb" ]; then
        echo "Error during protein preparation with Chimera" >> "$ERROR_LOG"
        exit 1
    fi

    # Prepare the protein using AutoDockTools
    $HOME/MGLTools-1.5.6/bin/python2.5 $HOME/MGLTools-1.5.6/MGLToolsPckgs/AutoDockTools/Utilities24/prepare_receptor4.py -r "$minimized_protein_pdb" -o "$output_pdbqt" -A hydrogens
    if [ $? -ne 0 ]; then
        echo "Error during protein preparation with AutoDockTools" >> "$ERROR_LOG"
        exit 1
    fi
}

# Function to convert ligand to PDBQT format using Open Babel
convert_ligand_to_pdbqt() {
    local ligand_sdf=$1
    local ligand_pdbqt=${ligand_sdf%.sdf}.pdbqt
    obabel "$ligand_sdf" -O "$ligand_pdbqt" --gen3D
    if [ $? -ne 0 ]; then
        echo "Error during ligand conversion to PDBQT" >> "$ERROR_LOG"
        exit 1
    fi
    echo "$ligand_pdbqt"
}

# Function to prepare ligand using AutoDockTools (ADT)
prepare_ligand() {
    local ligand_pdbqt=$1

    # Add hydrogens and check Gasteiger charges using Open Babel
    obabel "$ligand_pdbqt" -O "$ligand_pdbqt" --addh --partialcharge gasteiger
    if [ $? -ne 0 ]; then
        echo "Error during ligand hydrogen addition and charge assignment" >> "$ERROR_LOG"
        exit 1
    fi

    # Prepare the ligand using AutoDockTools
    $HOME/MGLTools-1.5.6/bin/python2.5 $HOME/MGLTools-1.5.6/MGLToolsPckgs/AutoDockTools/Utilities24/prepare_ligand4.py -l "$ligand_pdbqt" -o "$ligand_pdbqt" -A hydrogens
    return $?
}

# Function to check Gasteiger parameters
check_gasteiger_parameters() {
    local ligand_sdf=$1
    local ligand_pdbqt=$(convert_ligand_to_pdbqt "$ligand_sdf")
    local ligand_name=$(basename "$ligand_sdf" .sdf)

    if ! prepare_ligand "$ligand_pdbqt"; then
        echo "$ligand_name,Gasteiger parameters error" >> "$ERROR_LOG"
        return 1
    fi
    echo "$ligand_pdbqt"
    return 0
}

# Extract the binding site coordinates using the Python script
COORDINATES=$(get_binding_site_coordinates)
if [ -z "$COORDINATES" ]; then
    echo "Error: Failed to extract binding site coordinates."
    exit 1
fi

# Ensure coordinates are valid numbers
CENTER_X=$(echo "$COORDINATES" | awk '{print $1}')
CENTER_Y=$(echo "$COORDINATES" | awk '{print $2}')
CENTER_Z=$(echo "$COORDINATES" | awk '{print $3}')

# Check if coordinates are valid numbers
if ! [[ "$CENTER_X" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$CENTER_Y" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$CENTER_Z" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Error: Invalid binding site coordinates extracted: $COORDINATES"
    exit 1
fi

# Remove heteroatoms from the protein
CLEANED_PROTEIN=$(remove_heteroatoms "$PROTEIN" "$HETEROATOMS")

# Prepare the protein
PROTEIN_PDBQT="$SCRIPT_DIR/protein.pdbqt"
prepare_protein "$CLEANED_PROTEIN" "$PROTEIN_PDBQT"

# Generate a configuration file for Vina
cat <<EOL > "$CONFIG_FILE"
receptor = $PROTEIN_PDBQT
center_x = $CENTER_X
center_y = $CENTER_Y
center_z = $CENTER_Z
size_x = 20
size_y = 20
size_z = 20
exhaustiveness = 8
num_modes = 9
EOL

# Function to run AutoDock Vina for each ligand
dock_ligand() {
    local LIGAND=$1
    local LIGAND_NAME=$(basename "$LIGAND" .sdf)
    local LIGAND_OUTPUT_DIR="$OUTPUT_DIR/$LIGAND_NAME"
    local LIGAND_LOG="$LOG_DIR/$LIGAND_NAME.log"
    mkdir -p "$LIGAND_OUTPUT_DIR"

    # Prepare the ligand and check for Gasteiger parameters
    local LIGAND_PDBQT=$(check_gasteiger_parameters "$LIGAND")
    if [ $? -ne 0 ]; then
        echo "$LIGAND_NAME,Preparation error" >> "$ERROR_LOG"
        return 1
    fi

    # Run AutoDock Vina and redirect output to log file
    vina --config "$CONFIG_FILE" --ligand "$LIGAND_PDBQT" --out "$LIGAND_OUTPUT_DIR/out.pdbqt" > "$LIGAND_LOG" 2>&1
    
    # Check if Vina completed successfully
    if grep -q "Writing output" "$LIGAND_LOG"; then
        # Extract the best score from the log file and append to the summary log
        local SCORE=$(grep "REMARK VINA RESULT" "$LIGAND_LOG" | head -n 1 | awk '{print $4}')
        echo "$LIGAND_NAME,$SCORE" >> "$SUMMARY_LOG"

        # Merge the protein and ligand into one PDBQT file
        cat "$PROTEIN_PDBQT" "$LIGAND_OUTPUT_DIR/out.pdbqt" > "$LIGAND_OUTPUT_DIR/complex.pdbqt"
    else
        echo "$LIGAND_NAME,Vina docking error" >> "$ERROR_LOG"
    fi
}

# Loop through all ligand files in the ligand directory and dock them sequentially
for LIGAND in "$LIGAND_DIR"/*.sdf; do
    dock_ligand "$LIGAND"
done

echo "Docking completed. Docked poses are saved in $OUTPUT_DIR, log files are saved in $LOG_DIR, and summary log is saved in $SUMMARY_LOG. Errors are logged in $ERROR_LOG"
