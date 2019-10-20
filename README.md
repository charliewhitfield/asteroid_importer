# README #
I, Voyager add-on for creating asteroid binaries from source data files, mainly
from Asteroids Dynamic Site (https://newton.spacedys.com/astdys/).

### Installation ###
Add and maintain as submodule in your main project folder. The addon will add
its own button to the splash screen Main Menu. To use, however, you will need
to obtain asteroid source data as described below. Add source data to user
directory user://bigdata_source.

### Operation ###
The popup describes the import, more or less, and more documentation is in
the GDScript file. In general, each step must be done in order (some might
be skipped for troubleshooting or specialized use). Output binaries are written
to user://bigdata_binaries and must be added manually to the project directory 
(e.g., res://ivoyager/data/solar_system/proper_asteroid_binaries/).

### WIP ###
TODO: We will need to get epoch from AstDys-2 and add it as const setting
to AsteroidGroup, and then use it to correct all asteroid orbits to J2000.
TODO: The use of "proper" orbits is best suited for projects that need
reasonable orbits over large time scales. For present-day accuracy, it would
be better to generate binaries from current ephemerides. This would need an
entirely new importer using different source data. (Or maybe what we need
is here and we just need to skip "Revise Proper Orbits" step???)

### Source Files ###
astdys files https://newton.spacedys.com/astdys/ (comments are mostly copied)
Proper elements:
all.syn		Numbered and multiopposition asteroids; the catalog contains the
			Main Belt and Hungaria asteroids.
tno.syn		Trans Neptunian Objects; the catalog contains TNO's.
Orbital elements:
allnum.cat	Numbered asteroids orbital elements, one line format, epoch near
			present time.
ufitobs.cat	Multiopposition asteroids orbital elements, one line format, epoch
			near present time.
secres.syn	Main Belt asteroids locked in secular resonance. Please note that
			in this file the proper eccentricity is replaced by Delta e, the
			amplitude of resonant libration in the eccentricity. Thus the
			values in that column cannot be compared with those of the other
			files. In the visualizer the resonant objects are placed in an
			empty region with e between 0.7 and 0.8. with the convention
			e=Delta e + 0.7.
tro.syn		Trojan asteroids; the catalog contains Trojans.
all_tro.members	Individual asteroid family membership. Note only asteroids
			belonging to some family are listed in this file; Trojans are
			included.
all_tro.famtab	Asteroid families summary table for each family. Trojan and
			Griqua families are included.
all_tro.famrec	Family status for each asteroid with synthetic proper
			elements. Status=0 indicates the asteroid is not in any family,
			according to the current classification. Trojans are included.
numb.near	Very close couples (numbered only) . Candidates for binary
			splittings and recent families.

singopp.cat	Single opposition asteroids orbital elements, one line format,
			epoch near present time.
		
http://newton.dm.unipi.it/neodys
neodys.cat	Keplerian elements without covariance matrices
neodys.ctc	Equinoctial elements with covariance matrices
catalog.tot	Proper elements and encounter conditions
			
https://sbn.psi.edu/pds/resource/discover.html
discover.tab	Has name and discoverer for numbered asteroids as of 2008.
				File from EAR-A-5-DDR-ASTNAMES-DISCOVERY-V12.0/data.
			
