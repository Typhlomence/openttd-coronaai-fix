------ CoronaAI Fix ------
CoronaAI is a simple AI that attempts to build bus services in all cities on the map. The original version by Libor Vilimek works well enough, but has some bugs which I've elected to fix with this fork, without increasing the complexity by too much.

This is my first work on an AI (or any modification for OpenTTD), so there's probably implementation details that can be improved. Feel free to fork this if you want to improve it further, like I did!

On larger maps, the number of road vehicles should be increased. For example, on a 1024x1024 map, a maximum of 2500 should be used.

Main changes from the original CoronaAI:
* Makes sure to pick the highest capacity (by default) road vehicle that can run on the default road.
* More robust bus service construction to ensure properly running services (or clearing up if it fails to build one).
* Also more robust removal of unused services to avoid breaking services or leaving unused infrastructure.
* Supports saving and loading games, keeping its schedule and the information on its town infrastructure (Checks for existing infrastructure on AI start if there is no save data).
* Will check towns yearly (by default) to build infrastructure rather than only trying once.
* Better finances management such as repaying the loan and being stricter on unprofitable services when losing money.
* Will not sell old vehicles if there's currently no valid replacement.
* Four parameters for configuring time settings and criteria for choosing vehicles.

Limitations:
* Likely not to be compatible with all combinations of road vehicle and road type NewGRFs.
* Function for checking infrastructure when the game is loaded might not be correct 100% of the time.