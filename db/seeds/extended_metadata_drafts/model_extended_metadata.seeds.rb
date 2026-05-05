# Seeds file for adding extended metadata to a Model
puts 'Extended metadata for models'

configpath = File.join(Rails.root, 'config/default_data', 'model_attributes_descriptions.yml')
attribute_descriptions = YAML::load_file(configpath)

configpath = File.join(Rails.root, 'config/default_data', 'model_attributes_headings.yml')
attribute_headings = YAML::load_file(configpath)

boolean_type = SampleAttributeType.find_or_initialize_by(title: 'Boolean'
)
boolean_type.update(base_type: Seek::Samples::BaseType::BOOLEAN)

int_type = SampleAttributeType.find_or_initialize_by(title: 'Integer')
int_type.update(base_type: Seek::Samples::BaseType::INTEGER, placeholder: '1')

float_type = SampleAttributeType.find_or_initialize_by(title: 'Real number')
float_type.update(base_type: Seek::Samples::BaseType::FLOAT, placeholder: '0.5')

date_type = SampleAttributeType.find_or_initialize_by(title: 'Date')
date_type.update(base_type: Seek::Samples::BaseType::DATE, placeholder: 'January 1, 2024')

string_type = SampleAttributeType.find_or_initialize_by(title: 'String')

string_type.update(base_type: Seek::Samples::BaseType::STRING)

cv_type = SampleAttributeType.find_or_initialize_by(title: 'Controlled Vocabulary')
cv_type.update(base_type: Seek::Samples::BaseType::CV)

cv_type_list = SampleAttributeType.find_or_initialize_by(title: 'Controlled Vocabulary List')
cv_type_list.update(base_type: Seek::Samples::BaseType::CV_LIST)

text_type = SampleAttributeType.find_or_initialize_by(title: 'Text')
text_type.update(base_type: Seek::Samples::BaseType::TEXT, placeholder: '1'
)

def create_controlled_vocab_terms_attributes(array)
  attributes = []
  array.each do |type|
    attributes << { label: type }
  end
  attributes
end

disable_authorization_checks do

  # execution software cv
  execution_software_cv = SampleControlledVocab.where(title: 'Extended metadata for models - execution software').first_or_create!(
    sample_controlled_vocab_terms_attributes: create_controlled_vocab_terms_attributes(
      ['Unknown',
       'AMICI - Advanced Multilanguage Interface for CVODES and IDAS',
       'AUTO2000 - Software for continuation and bifurcation problems in ODEs',
       'BioCellion - multi-scale, agent-based HPC framework',
       'BioDynaMo - Biology Dynamics Modeller',
       'BioFVM - Finite Volume Method',
       'BioNetGen - structure-based modeling of biochemical reaction networks',
       'BNSim - agent-based cell simulator',
       'Bioscrape - Biological Stochastic Simulation of Single Cell Reactions and Parameter Estimation',
       'BioUML - Biological Universal Modelling Language',
       'BoolNet - R package for simulation and analysis of Boolean networks',
       'boolSim / genYsis - reduced ordered binary decision diagrams (ROBDDs) for Boolean modeling',
       'Brian - neural network simulator',
       'BSim - agent-Based Cell Simulator',
       'CancerSim - cancer simulation package',
       'CBMPy - Constrained Based Modelling Python',
       'CellDesigner',
       'CellNetAnalyzer (CNA)',
       'CellSys - Cell-based simulation software for multi-cellular systems',
       'Chaste - Cancer, Heart and Soft Tissue Environment',
       'CompCellBio - computational cell biology',
       'CompuCell3D - CC3D; environment for simulations of biocomplexity problems',
       'COPASI - Complex Pathway Simulator',
       'CPLEX - IBM ILOG CPLEX linear programming library',
       'CPN Tools - Colored Petri Nets',
       'E-Cell - multi-scale modeling, simulation and analysis of cells',
       'Escher-FBA - Flux Balance Analysis',
       'FLAME GPU - Flexible Large-Scale Agent Modelling Environment',
       'FLAME - Computational Fluid Dynamics Solver',
       'FlexFlux - metabolic flux and regulatory network analysis',
       'Fluxer - computation and visualization of flux graphs from genome-scale metabolic models',
       'Genetic Network Analyzer (GNA)',
       'Gepasi - biochemical kinetics simulator',
       'GillesPy - package for stochastic simulation of biochemical systems',
       'GINSim - Gene Interaction Network Simulation',
       'Gromacs - Groningen Machine for Chemical Simulations',
       'Hybrid Automata Library (HAL)',
       'iBioSim - modelling, analysis and design of gene circuits',
       'Insilico Discovery - Yokogawa Insilico Discovery',
       'jNeuroML - Java tool for working with LEMS and NeuroML 2',
       'JADE - simulation platform for synthetic biology',
       'Jarnac - metabolic analysis',
       'Julia - Julia programming language',
       'JWS Online - repository',
       'LBIBCell - Lattice Boltzmann Immersed Boundary',
       'libroadrunner - high-performance SBML solver for systems and synthetic biology',
       'LibSBMLSim - library for simulating SBML models',
       'MaBoSS - Markovian Boolean Stochastic Simulator',
       'MASSPy - Mass Action Stoichiometric Simulation python',
       'Mathematica - Wolfram Mathematica',
       'Matlab - MathWorks Matlab',
       'MCell - Monte Carlo cell',
       'MEDYAN - Mechanochemical Dynamics of Active Networks',
       'MesoRD - Mesoscopic Reaction Diffusion Simulator',
       'MetaNetX - genome-scale metabolic networks',
       'MeVisLab - Medical Visualization Lab',
       'Microvessel Chaste - library for Spatial Modeling of Vascularized Tissues',
       'MoBi - Multiscale physiological modelling and simulation',
       'MOP-C - molecular prognostic index for central nervous system lymphomas',
       'Morpheus - simulation environment for the study of multi-scale and multicellular systems',
       'MultiCellSim - agent-based multiscale model for a population of communicating cells',
       'MUSCLE - Multiscale Coupling Library and Environment',
       'NEURON - simulation environment for models of neurons and networks of neurons',
       'Octave - GNU Octave scientific programming language',
       'Open Knee - virtual biomechanical representations of the knee joint',
       'OpenCOBRA Toolbox - Constraints Based Reconstruction and Analysis',
       'OpenCOR - successor of COR and OpenCell',
       'OpenSim - modeling, simulating, controlling, and analysing the neuromusculo-skeletal system',
       'OptFlux - in silico metabolic engineering',
       'PathwayLab - PathwayLab Mathematica Package',
       'PhysiBoSS - PhysiCell-MaBoSS',
       'PhysiCell - physics-based cell simulator for cells in 3-D tissues',
       'PhysioDesigner - multilevel modeling of physiological systems',
       'PKSim - PharmacoKinetics Simulator',
       'PottersWheel - PottersWheel MATLAB toolbox',
       'pyNeuroML - simulation of NeuroML models',
       'PySB - systems biology modelling in Python',
       'PySCeS - Python simulator for cellular systems',
       'Python - Python programming language',
       'R - R project for statistical computing',
       'RAVEN - Reconstruction, Analysis and Visualization of Metabolic Networks',
       'ReaDDy - particle-based reaction-diffusion simulator',
       'Repast Simphony - suite of open-source, agent-based modelling and simulation platforms',
       'SBSCL - Systems Biology Simulation Core Library',
       'SBSI - Systems Biology Software Infrastructure',
       'SB Toolbox - Systems Biology Toolbox V2',
       'SBW - Systems Biology Workbench',
       'SimCells - multicellular simulations on multicore processors',
       'Simmune - simulation and analysis of immune system behaviour',
       'SimVascular - modelling of the cardiovascular system',
       'SmartCell - Spatial Modelling Algorithms for Reaction and Transport',
       'Smoldyn - spatial stochastic simulator for chemical reaction networks',
       'Snoopy - coloured hybrid Petri net simulation',
       'Spatiocyte - lattice-based particle simulator',
       'SpringSaLaD - particle-based, stochastic, biochemical simulation platform for modeling mesoscopic systems',
       'StochSS - Stochastic Simulation Service',
       'SyBME - Systems Biology Modelling Environment',
       'Tellurium - Tellurium simulator',
       'The Cell Collective - collaboratively building large-scale models',
       'Timothy - 3-D simulations of cell colonies',
       'TiSim / CellSys',
       'TissueForge - particle-based simulation environment',
       'Tissue Simulation Toolkit - TST; a library for Cellular Potts Models',
       'URDME - Unstructured Reaction-Diffusion Master Equation',
       'VCell (Virtual Cell)',
       'Vivarium - engine for integrative multiscale modeling',
       'winBEST-KIT - Windows-based Biochemical Engineering System Tool-KIT',
       'XPP / XPPAUT - X-Windows Phase Plane plus Auto',
       'Yalla - yet another parallel agent-based model for morphogenesis'
      ]
    )
  )

  # execution_software
  execution_software_label = ExtendedMetadataAttribute.find_or_initialize_by(title: 'execution_software_label')
  execution_software_label.update(
    title: 'execution_software_label', required: true, sample_attribute_type: cv_type, sample_controlled_vocab: execution_software_cv,
    description: attribute_descriptions['execution_software'], label: attribute_headings['execution_software'], pos:1
  )

  # age
  age_label = ExtendedMetadataAttribute.find_or_initialize_by(title: 'age_label')
  age_label.update(
    title: 'age_label', required: true, sample_attribute_type: int_type,
    description: attribute_descriptions['age'], label: attribute_headings['age'], pos:2
  )

  # ontologies cv (list from OLS4 (Open Lookup Service))
  ontologies_cv = SampleControlledVocab.where(title: 'Extended metadata for models - ontologies').first_or_create!(
    sample_controlled_vocab_terms_attributes: create_controlled_vocab_terms_attributes(
      ['Anatomical Entity Ontology (AEO)',
       "Alzheimer's Disease Ontology (ADO)",
       'Adverse Event Reporting Ontology (AERO)',
       'Allotrope Merged Ontology Suite (AFO)',
       'Agronomy Ontology (AGRO)',
       'Ontology for the Anatomy of the Insect SkeletoMuscular system (AISM)',
       'Amphioxus Development and Anatomy Ontology (AMPHX)',
       'Ascomycete Phenotype Ontology (APO)',
       'Apollo Structured Vocabulary (APOLLO_SV)',
       'Antibiotic Resistance Ontology (ARO)',
       'BioAssay Ontology (BAO)',
       'Beta Cell Genomics Ontology (BCGO)',
       'The Behaviour Change Intervention Ontology (BCIO)',
       'Biological Collections Ontology (BCO)',
       'Basic Formal Ontology (BFO)',
       'Bilateria anatomy (BILA)',
       'Biological Spatial Ontology (BSPO)',
       'The BRENDA Tissue Ontology (BTO)',
       'Chemical Analysis Metadata Platform (CAO)',
       'Common Anatomy Reference Ontology (CARO)',
       'Human Reference Atlas Common Coordinate Framework Ontology (CCF)',
       'Cell Cycle Ontology (CCO)',
       'Comparative Data Analysis Ontology (CDAO)',
       'Compositional Dietary Nutrition Ontology (CDNO)',
       'Cephalopod Ontology (CEPH)',
       'Chemical Entities of Biological Interest (CHEBI)',
       'chemical information ontology (CHEMINF)',
       'CHEBI Integrated Role Ontology (CHIRO)',
       'Chemical Methods Ontology (CHMO)',
       'CIDO: Ontology of Coronavirus Infectious Disease (CIDO)',
       'Confidence Information Ontology (CIO)',
       'Cell Ontology (CL)',
       'Collembola Anatomy Ontology (CLAO)',
       'CLO: Cell Line Ontology (CLO)',
       'Clytia hemisphaerica Development and Anatomy Ontology (CLYH)',
       'Clinical measurement ontology (CMO)',
       'Cellular Microscopy Phenotype Ontology (CMPO)',
       'Core Ontology for Biology and Biomedicine (COB)',
       'Coleoptera Anatomy Ontology (COLAO)',
       'CoVoc Coronavirus Vocabulary (COVOC)',
       'Critical Path Ontology (CPONT)',
       'Contributor Role Ontology (CRO)',
       'Cryo Electron Microscopy ontology (CRYOEM)',
       'Ctenophore Ontology (CTENO)',
       'Dublin core elements (DC)',
       'Dublin core terms (DCTERMS)',
       'Dicty Anatomy Ontology (DDANAT)',
       'Dicty Phenotype Ontology (DDPHENO)',
       'DICOM Controlled Terminology (DICOM)',
       'Drug-drug Interaction and Drug-drug Interaction Evidence Ontology (DIDEO)',
       'Disease Drivers (DISDRIV)',
       'Human Disease Ontology (DOID)',
       'Drosophila Phenotype Ontology (FBCV)',
       'The Drug Ontology (DRON)',
       'Data Use Ontology (DUO)',
       'Echinoderm Anatomy and Development Ontology (ECAO)',
       'Evidence & Conclusion Ontology (ECO)',
       'An ontology of core ecological entities (ECOCORE)',
       'Environment Exposure Ontology (ECTO)',
       'Bioinformatics operations, data types, formats, identifiers and topics (EDAM)',
       'Experimental Factor Ontology (EFO)',
       'Human developmental anatomy, abstract (EHDAA2)',
       'Mouse gross anatomy and development, timed (EMAP)',
       'Mouse Developmental Anatomy Ontology (EMAPA)',
       'eNanoMapper ontology (ENM)',
       'Ensembl Glossary (ENSGLOSS)',
       'The Environment Ontology (ENVO)',
       'Epilepsy Ontology (EPIO)',
       'VEuPathDB Ontology (EUPATH)',
       'Exposure ontology (EXO)',
       'Fungal gross anatomy (FAO)',
       'Biological Imaging Methods Ontology (FBBI)',
       'Drosophila gross anatomy (FBBT)',
       'FlyBase Controlled Vocabulary (FBCV)',
       'Drosophila Developmental Ontology (FBDV)',
       'Fly taxonomy (FBSP)',
       'Food Interactions with Drugs Evidence Ontology (FIDEO)',
       'Physico-chemical methods and properties (FIX)',
       'Flora Phenotype Ontology (FLOPO)',
       'Foundational Model of Anatomy Ontology (FMA)',
       'Food-Biomarker Ontology (FOBI)',
       'Food Ontology (FOODON)',
       'FuTRES Ontology of Vertebrate Traits (FOVT)',
       'Fission Yeast Phenotype Ontology (FYPO)',
       'Gazetteer (GAZ)',
       'Genomics Cohorts Knowledge Ontology (GECKO)',
       'Genomic Epidemiology Ontology (GENEPIO)',
       'GENO ontology (GENO)',
       'Geographical Entity Ontology (GEO)',
       'Gene Expression Ontology (GEXO)',
       'Glycan Naming Ontology (GNO)',
       'Gene Ontology (GO)',
       'GSSO - the Gender, Sex, and Sexual Orientation ontology (GSSO)',
       'Human Ancestry Ontology (HANCESTRO)',
       'Hymenoptera Anatomy Ontology (HAO)',
       'Human Cell Atlas Ontology (HCAO)',
       'Homology Ontology (HOM)',
       'Human Phenotype Ontology (HP)',
       'Human Developmental Stages (HSAPDV)',
       'Health Surveillance Ontology (HSO)',
       'Hypertension Ontology For Clinical Data (HTN)',
       'Information Artifact Ontology (IAO)',
       'ICEO: Ontology of Integrative and Conjugative Elements (ICEO)',
       'Informed Consent Ontology (ICO)',
       'Infectious Disease Ontology (IDO)',
       'The COVID-19 Infectious Disease Ontology (IDO-COVID-19)',
       'Malaria Ontology (IDOMAL)',
       'INO: Interaction Network Ontology (INO)',
       'Kinetic Simulation Algorithm Ontology (KISAO)',
       'clinical LABoratory Ontology (LABO)',
       'Lepidoptera Anatomy Ontology (LEPAO)',
       'LIPID MAPS (LIPIDMAPS)',
       'Mouse adult gross anatomy (MA)',
       'Mathematical Modelling Ontology (MAMO)',
       'Medical Action Ontology (MAXO)',
       'Microbial Conditions Ontology (MCO)',
       'Model Card Report Ontology (MCRO)',
       'Mental Functioning Ontology (MF)',
       'Mammalian Feeding Muscle Ontology (MFMO)',
       'Emotion Ontology (MFOEM)',
       'Mental Disease Ontology (MFOMD)',
       'Molecular Interactions Controlled Vocabulary (MI)',
       'Minimum Information for A Phylogenetic Analysis (MIAPA)',
       'Ontology of Prokaryotic Phenotypic and Metabolic Characters (MICRO)',
       'Mosquito insecticide resistance (MIRO)',
       'Measurement method ontology (MMO)',
       'Mouse Developmental Stages (MMUSDV)',
       'Protein modification (MOD)',
       'Mondo Disease Ontology (MONDO)',
       'MOP (MOP)',
       'The Mammalian Phenotype Ontology (MP)',
       'Mouse pathology ontology (MPATH)',
       'Minimum PDDI Information Ontology (MPIO)',
       'MHC Restriction Ontology (MRO)',
       'Mass spectrometry ontology (MS)',
       'Metabolomics Standards Initiative Ontology (MSIO)',
       'Neuro Behavior Ontology (NBO)',
       'NCBI organismal classification (NCBITAXON)',
       'NCI Thesaurus OBO Edition (NCIT)',
       'Non-Coding RNA Ontology (NCRO)',
       'Next generation biobanking ontolog (NGBO)',
       'nuclear magnetic resonance CV (NMR)',
       'NOMEN - A nomenclatural ontology for biological names (NOMEN)',
       'OAE: Ontology of Adverse Events (OAE)',
       'Ontology of Arthropod Circulatory Systems (OARCS)',
       'Ontology of Biological Attributes (OBA)',
       'OBCS: Ontology of Biological and Clinical Statistics (OBCS)',
       'Ontology for Biomedical Investigations (OBI)',
       'Ontology for BIoBanking (OBIB)',
       'Occupation Ontology (OCCO)',
       'OGG: Ontology of Genes and Genomes (OGG)',
       'Ontology for General Medical Science (OGMS)',
       'Ontology of Genetic Susceptibility Factor (OGSF)',
       'Oral Health and Disease Ontology (OHD)',
       'OHMI: Ontology of Host-Microbiome Interactions (OHMI)',
       'OHPI: Ontology of Host-Pathogen Interactions (OHPI)',
       'Ontology of units of Measure (OM)',
       'Ontologized MIABIS (OMIABIS)',
       'Ontology for MIRNA Target (OMIT)',
       'OBO Metadata Ontology (OMO)',
       'Ontology of Microbial Phenotypes (OMP)',
       'Ontology for Modeling and Representation of Social Entities (OMRSE)',
       'Ontology for Nutritional Epidemiology (ONE)',
       'Ontology for Nutritional Studies (ONS)',
       'OntoAvida: ontology for Avida digital evolution platform. (ONTOAVIDA)',
       'Obstetric and Neonatal Ontology (ONTONEO)',
       'Ontology of Organizational Structures of Trauma centers and Trauma Systems (OOSTT)',
       'Ontology for Parasite Lifecycle (OPL)',
       'OPMI: Ontology of Precision Medicine and Investigation (OPMI)',
       'Orphanet Rare Disease Ontology (ORDO)',
       'Ontology for RNA sequencing (ORNASEQ)',
       'Orthology Ontology (ORTH)',
       'OVAE: Ontology of Vaccine Adverse Events (OVAE)',
       'The OWL 2 Schema vocabulary (OWL)',
       'PATO - the Phenotype And Trait Ontology (PATO)',
       'Provisional Cell Ontology (PCL)',
       'Population and Community Ontology (PCO)',
       'The Prescription of Drugs Ontology (PDRO)',
       'Pathogen Host Interactions Phenotype Ontology (PHIPO)',
       'Planarian Anatomy Ontology (PLANA)',
       'Planarian Phenotype Ontology (PLANP)',
       'Plant Ontology (PO)',
       'Porifera (PORO)',
       'Plant Phenology Ontology (PPO)',
       'PRotein Ontology (PR)',
       'PRIDE Controlled Vocabulary (PRIDE)',
       'Probability Distribution Ontology (PROBONTO)',
       'PROCO: PROcess Chemistry Ontology (PROCO)',
       'Provenance Ontology (PROV)',
       'Performance Summary Display Ontology (PSDO)',
       'Plant Stress Ontology (PSO)',
       'Pathway ontology (PW)',
       'Radiation Biology Ontology (RBO)',
       'The RDF Schema vocabulary (RDFS)',
       'REPRODUCE-ME Ontology (REPR)',
       'Regulation of Transcription Ontology (RETO)',
       'Physico-chemical process (REX)',
       'Regulation of Gene Expression Ontology (REXO)',
       'Relation Ontology (RO)',
       'Rat Strain Ontology (RS)',
       'RXNO (RXNO)',
       'Systems Biology Ontology (SBO)',
       'Sickle Cell Disease Ontology (SCDO)',
       'Semantic Mapping Vocabulary (SEMAPV)',
       'Ontology for Scientific Evidence and Provenance Information (SEPIO)',
       'ShareLoc (SHARELOC)',
       'Social Insect Behavior Ontology (SIBO)',
       'Semanticscience Integrated Ontology (SIO)',
       'SwissLipids (SLM)',
       'SNOMED CT (SNOMED)',
       'Sequence types and features ontology (SO)',
       'Spider Ontology (SPD)',
       'FAIRsharing Subject Ontology (SRAO)',
       'STATO: the statistical methods ontology (STATO)',
       'Software ontology (SWO)',
       'Symptom Ontology (SYMP)',
       'terms4FAIRskills (T4FS)',
       'Tick Anatomy Ontology (TADS)',
       'Teleost Anatomy Ontology (TAO)',
       'Taxonomic rank vocabulary (TAXRANK)',
       'Terminology for Description of Dynamics (TEDDY)',
       'Mosquito gross anatomy ontology (TGMA)',
       'Plant Trait Ontology (TO)',
       'Pathogen Transmission Ontology (TRANS)',
       'Teleost taxonomy ontology (TTO)',
       'TOXic Process Ontology (TXPO)',
       'Uber-anatomy ontology (UBERON)',
       'Unimod protein modification database for mass spectrometry (UNIMOD)',
       'Units of measurement ontology (UO)',
       'Unipathway (UPA)',
       'Vertebrate Breed Ontology (VBO)',
       'Vaccine Ontology (VO)',
       'Vertebrate Skeletal Anatomy Ontology- (VSAO)',
       'The Vertebrate Trait Ontology (VT)',
       'Vertebrate Taxonomy Ontology (VTO)',
       'C. elegans Gross Anatomy Ontology (WBBT)',
       'C. elegans Development Ontology (WBLS)',
       'C elegans Phenotype Ontology (WBPHENOTYPE)',
       'Xenopus Anatomy Ontology (XAO)',
       'Experimental condition ontology (XCO)',
       'HUPO-PSI cross-linking and derivatization reagents controlled vocabulary (XLMOD)',
       'Xenopus Phenotype Ontology (XPO)',
       'Zebrafish Experimental Conditions Ontology (ZECO)',
       'Zebrafish Anatomy Ontology (ZFA)',
       'Zebrafish developmental stages ontology (ZFS)',
       'Zebrafish Phenotype Ontology (ZP)'
      ]
    )
  )

  # ontologies
  ontologies_label = ExtendedMetadataAttribute.new(title: 'ontologies_label', required:false,
	  sample_attribute_type: SampleAttributeType.where(title: 'Controlled Vocabulary List').first,
		sample_controlled_vocab: ontologies_cv,
		description: attribute_descriptions['ontologies'], label: attribute_headings['ontologies'], pos:3
		)

  # scale cv
  scale_cv = SampleControlledVocab.where(title: 'Extended metadata for models - scale (qualitative)').first_or_create!(
    sample_controlled_vocab_terms_attributes: create_controlled_vocab_terms_attributes(
      %w[molecular organelle cell tissue organ system body community]
    )
  )

  # scale
  scale_label = ExtendedMetadataAttribute.find_or_initialize_by(title: 'scale_label')
  scale_label.update(
    title: 'scale_label', required: true, sample_attribute_type: cv_type, sample_controlled_vocab: scale_cv,
    description: attribute_descriptions['scale'], label: attribute_headings['scale'], pos:4
  )

  # credibility
  credibility_label = ExtendedMetadataAttribute.find_or_initialize_by(title: 'credibility_label')
  credibility_label.update(
    title: 'credibility_label', required: true, sample_attribute_type: float_type,
    description: attribute_descriptions['credibility'], label: attribute_headings['credibility'], pos:5
  )

  # clustering
  clustering_label = ExtendedMetadataAttribute.find_or_initialize_by(title: 'clustering_label')
  clustering_label.update(
    title: 'clustering_label', required: true, sample_attribute_type: float_type,
    description: attribute_descriptions['clustering'], label: attribute_headings['clustering'], pos:6
  )

  unless ExtendedMetadataType.where(title:'Extended Metadata for models v2', supported_type:'Model').any?
    cmt = ExtendedMetadataType.new(title: 'Extended Metadata for models v2', supported_type:'Model')
    cmt.extended_metadata_attributes << execution_software_label
    cmt.extended_metadata_attributes << age_label
    cmt.extended_metadata_attributes << ontologies_label
    cmt.extended_metadata_attributes << scale_label
    cmt.extended_metadata_attributes << credibility_label
    cmt.extended_metadata_attributes << clustering_label

    cmt.save!
    puts 'Extended metadata for models'
  end 
     
end 