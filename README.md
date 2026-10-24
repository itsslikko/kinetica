# Kinetica: Kinetic Automation for Mineclonia

**Kinetica** brings mechanical power, dynamic logistics, and emergent factory automation to Mineclonia and VoxeLibre, heavily inspired by the beloved Create mod.

Harness the power of water and steam to generate Rotational Power (KU), transmit it through shafts and gearboxes, and power a massive arsenal of processing machines. Say goodbye to magic blocks—in Kinetica, you build the factory.

## The Progression Era

**Tier 1: Basic Kinetics (Andesite & Wood)**
*   **Andesite Alloy:** The foundational binder, crafted from Andesite and Iron Ingots.
*   **Water Wheels:** Generate early-game kinetic power from flowing water.
*   **Shafts, Gearboxes & Chain Drives:** Transmit power around corners, vertically, and across wide factory floors.

**Tier 2: Heavy Industry (Iron)**
*   **Mechanical Press:** The gateway to mid-game. Stamp raw Iron, Copper, and Gold ingots into sheets, or compact 9x nuggets into ingots automatically.
*   **Mechanical Drill & Saw:** Automate cobblestone generators and tree farms.
*   **Encased Fan:** Wash, blast, or haunt items directly on conveyor belts.
*   **Crushing Wheels:** Grind ores and cobblestone into gravel and sand.

**Tier 3: Fluids & Steam (Copper)**
*   **Water Pumps & Fluid Pipes:** Move water vertically and horizontally.
*   **Steam Generators & Turbines:** Burn fuel to boil water and generate massive amounts of high-speed Kinetic Units (KU) for late-game mega-factories.

**Tier 4: Smart Logistics (Gold/Brass)**
*   **Mechanical Belts & Depots:** Transport items smoothly across your factory.
*   **Chutes:** Drop items vertically into containers.
*   **Funnels & Smart Funnels:** The ultimate sorting tools. Attach Smart Funnels to the sides of passing belts to drag specific items off the line using 3-slot ghost filters, category matching, and exact-count batching!

## The Engineer's Glasses
Never guess why a machine stopped working. Craft the **Kinetic Engineer's Glasses** (Glass + Gold Ingot) and wear them in your helmet slot. Looking at any kinetic machine will display a live left-side HUD showing:
*   Current RPM and network stress.
*   Available vs. Consumed Kinetic Units (KU).
*   Live item filtering, batch sizes, and flow direction for Funnels.

## Building Infinite Factories
Kinetica is designed for emergent automation. By chaining machines together, you can create infinite resource loops:
*   **Infinite Iron:** Drill Cobblestone, Crush into Gravel, Wash with Fan (Yields Iron Nuggets), Smart Funnel sorts Nuggets, Mechanical Press compacts 9 Nuggets into 1 Iron Ingot.

## Dependencies
This mod is designed specifically for **Mineclonia** and **VoxeLibre** and relies on standard APIs (`mcl_core`, `mcl_sounds`, `mcl_formspec`, `mcl_experience`, `mcl_pistons`, `mcl_redstone`).

---

## Media Credits & Licenses

**3D Models:**
*   `kinetica_water_wheel_big.obj`: Original work created entirely by Slikko. 
*   **License:** CC BY-SA 4.0

**Textures:**
*   **Original Textures:** All custom machine casings, belts, and UI textures were created by Slikko. Licensed under CC BY-SA 4.0.
*   **Mineclonia / VoxeLibre Assets:** Textures for the piston, stone cutter drill, steam maker (`steam_maker_down.png`, `steam_maker_side.png`, `steam_maker_front_off.png`), pipe (`pipe.png`), and water wheel core (`water_wheel_core.png`) are copied or derived from the Mineclonia/VoxeLibre project. 
*   **License:** These specific derivative files inherit the original CC BY-SA 4.0 license. Full credit to the Mineclonia and VoxeLibre contributors for the base assets.

**Audio:**
*   This mod does not currently bundle any custom sound files.