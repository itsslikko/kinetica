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
*   **Chutes & Funnels:** Drop items vertically into containers, or use Smart Funnels to drag specific items off moving belts using 3-slot ghost filters, category matching, and exact-count batching.
*   **Item Vaults:** Large-capacity, multi-block storage that can be safely glued to moving piston contraptions.
*   **Portable Interfaces:** Bridge static automation lines with moving contraptions (and Steampunk Blimps) to automatically refuel, repair, and transfer fluids and cargo on the fly.

## The Engineer's Glasses
Never guess why a machine stopped working. Craft the **Kinetic Engineer's Glasses** (Glass + Gold Ingot) and wear them in your helmet slot. Looking at any kinetic machine will display a live left-side HUD showing:
*   Current RPM and network stress.
*   Available vs. Consumed Kinetic Units (KU).
*   Live item filtering, batch sizes, and flow direction for Funnels.
*   Contents and capacities of multi-block Item Vaults.

## Dependencies
This mod is designed specifically for **Mineclonia** and **VoxeLibre** and relies on standard APIs (`mcl_core`, `mcl_sounds`, `mcl_formspec`, `mcl_experience`, `mcl_pistons`, `mcl_redstone`).
*   **Optional Integration:** `steampunk_blimp` (Auto-refueling and cargo transfer via Portable Interfaces).

---

## Media Credits & Licenses

**3D Models:**
*   `kinetica_water_wheel_big.obj`: Original 3D model created by **Slikko** (CC BY-SA 4.0).

**Textures:**
*   **Original Hand-Painted Textures (by Slikko — CC BY-SA 4.0):** All custom casings (`andisite`, `copper`, `gold`), speed controller, gearbox, chain drive, encased fan, chute, feeder, water pump, steam turbine, belts, shafts, glue, vaults, portable interfaces, and engineer's glasses were hand-painted by **Slikko**.
*   **Mineclonia / VoxeLibre Assets (CC BY-SA 4.0):** `kinetica_pipe.png`, `kinetica_water_wheel_core.png`, and the steam generator textures are copied or modified from **Mineclonia** / **VoxeLibre** (based on **Pixel Perfection** by **XSSheep** and Mineclonia/VoxeLibre contributors).

**Audio:**
*   **Original Audio (by Slikko — CC BY-SA 4.0):** Drills, crushers, saws, fans, steam generators, water pumps, and turbines.