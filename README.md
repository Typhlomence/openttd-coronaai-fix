# CoronaAI Fix (openttd-coronaai-fix)
CoronaAI is a simple AI that attempts to build bus services in all cities on the map. The [original version](https://www.tt-forums.net/viewtopic.php?p=1238174) by Libor Vilimek works well enough, but has some bugs which I've elected to fix with this fork, without increasing the complexity by too much.

This is my first work on an AI (or any modification for OpenTTD), so there's probably implementation details that can be improved. Feel free to fork this if you want to improve it further, like I did!

On larger maps, the number of road vehicles should be increased. For example, on a 1024x1024 map, a maximum of 2500 should be used.

Changes from the original CoronaAI:
* Selecting vehicles:
    * Will make sure to pick a passenger road vehicle that can run on the default road type (i.e. not a tram). If none can be found, the AI will not build anything but will wait until one is available.
* Building stations, depots and buses:
    * Ensure that the company actually built them on the chosen tiles (no matter the road type).
    * Ensure that a depot was built before trying to buy a bus.
    * Ensure that a bus was bought.
    * Ensure stations and depots are connected to each other by existing roads.
    * Don't build outside of the current town's local authority (which can cause issues if a big town is next to a small town).
* Removing unused stations and depots:
    * Try again later if the operation was unsuccessful (e.g. another company's vehicle was in the way).
    * Only try to remove them if both stations are unused (see limitations).
* On AI start, will attempt to look for existing stations, depots and buses (so that it does not rebuild everything again when loading a saved game).
* After going through all towns, will wait a year before going through them again to (re)build in towns that currently have no service.
* Finances:
    * Will repay the loan if there's enough spare money.
    * Will take out a loan (if it doesn't have one already) if running low on money.
    * Will sell any unprofitable vehicles (rather than just highly unprofitable) when running low on money and if the loan is at maximum.
* Replacing old vehicles:
    * On AI start, turn off auto-renew to not interfere with sending old vehicles to the depot (which would lead to depots full of auto-renewed vehicles).
    * Do not try to sell old vehicles if there's no available replacement (and any in depots already will be sent back out).
    * If buying a replacement vehicle fails for the last vehicle on the route, keep the old vehicle around until it can be replaced (if it can).

Limitations:
* Likely not to be compatible with all combinations of road vehicle and road type NewGRFs.
* Because checking for existing infrastructure is a rough check, it might not be correct 100% of the time. To try to prevent issues, the function for deleting unused stations and depots checks if both found stations are not in use.