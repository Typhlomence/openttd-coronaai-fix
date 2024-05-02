# CoronaAI Fix (openttd-coronaai-fix)
CoronaAI is a simple AI that attempts to build bus services in all cities on the map. The original version by Libor Vilimek works well enough, but has some bugs which I've elected to fix with this fork, without increasing the complexity by too much.

This is my first work on an AI (or any modification for OpenTTD), so there's probably implementation details that can be improved.

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

Limitations:
* Likely not to be compatible with all combinations of road vehicle and road type NewGRFs.
* Because checking for existing infrastructure is a rough check, it might not be correct 100% of the time. To try to prevent issues, the function for deleting unused stations and depots checks if both found stations are not in use.

# Original readme of ottd-coronaai
Please increase number of road vehicles per company (in settings -> limitations).
On 1024x1024 map the preffered number is 2500.

 * This is very simple AI that was written while I was ill due to having covid-19.
 * I spent only two partial days working on it, therefore it really is intended to be simple.
 * It will try to spread to all cities with buses alone.
 
 Free to use
