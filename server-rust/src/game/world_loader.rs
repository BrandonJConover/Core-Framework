//! Load Java/OpenRSC world location data into neutral Rust spawn structures.
//!
//! This module intentionally stops at data translation. Applying spawns to the
//! live [`World`](super::world::World) and deriving collision flags from object
//! definitions can happen in later, smaller parity slices.

use std::fs;
use std::io;
use std::path::Path;

use serde::Deserialize;

use super::entity::Position;
use super::game_object::ObjectType;
use super::item::ItemId;
use super::region::{GroundItemSpawn, NpcSpawn, ObjectSpawn, SpawnManager};

#[derive(Debug, Deserialize)]
struct JavaPoint {
    #[serde(rename = "X")]
    x: i32,
    #[serde(rename = "Y")]
    y: i32,
}

#[derive(Debug, Deserialize)]
struct JavaNpcLoc {
    id: u32,
    start: JavaPoint,
    min: JavaPoint,
    max: JavaPoint,
}

#[derive(Debug, Deserialize)]
struct JavaNpcLocs {
    npclocs: Vec<JavaNpcLoc>,
}

#[derive(Debug, Deserialize)]
struct JavaObjectLoc {
    id: u32,
    pos: JavaPoint,
    direction: u8,
}

#[derive(Debug, Deserialize)]
struct JavaSceneryLocs {
    sceneries: Vec<JavaObjectLoc>,
}

#[derive(Debug, Deserialize)]
struct JavaBoundaryLocs {
    boundaries: Vec<JavaObjectLoc>,
}

#[derive(Debug, Deserialize)]
struct JavaGroundItemLoc {
    id: u32,
    pos: JavaPoint,
    amount: u32,
    respawn: u32,
}

#[derive(Debug, Deserialize)]
struct JavaGroundItemLocs {
    grounditems: Vec<JavaGroundItemLoc>,
}

fn invalid_data(error: serde_json::Error) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error)
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> io::Result<T> {
    let source = fs::read_to_string(path)?;
    serde_json::from_str(&source).map_err(invalid_data)
}

/// Load Java `NpcLocs*.json` into neutral NPC spawn definitions.
pub fn load_java_npc_locs(path: &Path) -> io::Result<Vec<NpcSpawn>> {
    let locs: JavaNpcLocs = read_json(path)?;
    Ok(locs
        .npclocs
        .into_iter()
        .map(|loc| {
            NpcSpawn::with_bounds(
                loc.id,
                Position::new(loc.start.x, loc.start.y),
                loc.min.x,
                loc.max.x,
                loc.min.y,
                loc.max.y,
            )
        })
        .collect())
}

/// Load Java `SceneryLocs*.json` into neutral scenery object spawn definitions.
pub fn load_java_scenery_locs(path: &Path) -> io::Result<Vec<ObjectSpawn>> {
    let locs: JavaSceneryLocs = read_json(path)?;
    Ok(locs
        .sceneries
        .into_iter()
        .map(|loc| {
            ObjectSpawn::new(
                loc.id,
                Position::new(loc.pos.x, loc.pos.y),
                loc.direction,
                ObjectType::Scenery,
            )
        })
        .collect())
}

/// Load Java `BoundaryLocs*.json` into neutral boundary object spawn definitions.
pub fn load_java_boundary_locs(path: &Path) -> io::Result<Vec<ObjectSpawn>> {
    let locs: JavaBoundaryLocs = read_json(path)?;
    Ok(locs
        .boundaries
        .into_iter()
        .map(|loc| {
            ObjectSpawn::new(
                loc.id,
                Position::new(loc.pos.x, loc.pos.y),
                loc.direction,
                ObjectType::Boundary,
            )
        })
        .collect())
}

/// Load Java `GroundItems*.json` into neutral ground item spawn definitions.
pub fn load_java_ground_item_locs(path: &Path) -> io::Result<Vec<GroundItemSpawn>> {
    let locs: JavaGroundItemLocs = read_json(path)?;
    Ok(locs
        .grounditems
        .into_iter()
        .map(|loc| {
            GroundItemSpawn::new(
                ItemId(loc.id),
                loc.amount,
                Position::new(loc.pos.x, loc.pos.y),
                loc.respawn,
            )
        })
        .collect())
}

/// Load the base Java loc file family from a `conf/server/defs/locs` directory.
pub fn load_base_java_locs_dir(locs_dir: &Path) -> io::Result<SpawnManager> {
    let mut spawns = SpawnManager::new();

    for spawn in load_java_npc_locs(&locs_dir.join("NpcLocs.json"))? {
        spawns.add_npc_spawn(spawn);
    }
    for spawn in load_java_scenery_locs(&locs_dir.join("SceneryLocs.json"))? {
        spawns.add_object_spawn(spawn);
    }
    for spawn in load_java_boundary_locs(&locs_dir.join("BoundaryLocs.json"))? {
        spawns.add_object_spawn(spawn);
    }
    for spawn in load_java_ground_item_locs(&locs_dir.join("GroundItems.json"))? {
        spawns.add_ground_item_spawn(spawn);
    }

    Ok(spawns)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn java_locs_dir() -> &'static Path {
        Path::new(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../server-java-modern/conf/server/defs/locs"
        ))
    }

    #[test]
    fn loads_base_java_npc_locs_with_known_first_entry() {
        let npcs = load_java_npc_locs(&java_locs_dir().join("NpcLocs.json")).unwrap();

        assert_eq!(npcs.len(), 3608);
        assert_eq!(npcs[0].npc_id, 401);
        assert_eq!(npcs[0].position, Position::new(413, 11));
        assert_eq!((npcs[0].min_x, npcs[0].min_y), (411, 9));
        assert_eq!((npcs[0].max_x, npcs[0].max_y), (413, 12));
    }

    #[test]
    fn loads_base_java_object_locs_with_type_split() {
        let scenery = load_java_scenery_locs(&java_locs_dir().join("SceneryLocs.json")).unwrap();
        let boundaries =
            load_java_boundary_locs(&java_locs_dir().join("BoundaryLocs.json")).unwrap();

        assert_eq!(scenery.len(), 26814);
        assert_eq!(scenery[0].object_id, 70);
        assert_eq!(scenery[0].position, Position::new(389, 2));
        assert_eq!(scenery[0].direction, 0);
        assert_eq!(scenery[0].object_type, ObjectType::Scenery);

        assert_eq!(boundaries.len(), 967);
        assert_eq!(boundaries[0].object_id, 1);
        assert_eq!(boundaries[0].position, Position::new(424, 18));
        assert_eq!(boundaries[0].direction, 1);
        assert_eq!(boundaries[0].object_type, ObjectType::Boundary);
    }

    #[test]
    fn loads_base_java_ground_items_with_respawn_data() {
        let items = load_java_ground_item_locs(&java_locs_dir().join("GroundItems.json")).unwrap();

        assert_eq!(items.len(), 1019);
        assert_eq!(items[0].item_id, ItemId(738));
        assert_eq!(items[0].position, Position::new(426, 15));
        assert_eq!(items[0].amount, 1);
        assert_eq!(items[0].respawn_ticks, 30);
    }

    #[test]
    fn loads_base_java_locs_dir_into_spawn_manager() {
        let spawns = load_base_java_locs_dir(java_locs_dir()).unwrap();

        assert_eq!(spawns.npc_spawns.len(), 3608);
        assert_eq!(spawns.object_spawns.len(), 27781);
        assert_eq!(spawns.ground_item_spawns.len(), 1019);
        assert_eq!(spawns.total_spawns(), 32408);
    }
}
