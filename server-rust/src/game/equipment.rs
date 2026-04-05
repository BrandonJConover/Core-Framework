//! Player equipment system.
//! Handles worn items, equipment bonuses, and equipment validation.

use std::collections::HashMap;
use tracing::{debug, info, warn};

use super::item::{CombatBonuses, EquipSlot, ItemDef, ItemId, ItemRepository, ItemRequirements};
use super::inventory::{Inventory, InventoryItem};
use super::skills::Skills;

/// Equipment slot mapping for RSC.
/// RSC has a simpler equipment system than later versions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EquipmentSlot {
    Head,
    Cape,
    Amulet,
    Weapon,
    Body,
    Shield,
    Legs,
    Hands,
    Feet,
    Ring,
    Ammo,
}

impl EquipmentSlot {
    /// Get all equipment slots.
    pub fn all() -> &'static [EquipmentSlot] {
        &[
            EquipmentSlot::Head,
            EquipmentSlot::Cape,
            EquipmentSlot::Amulet,
            EquipmentSlot::Weapon,
            EquipmentSlot::Body,
            EquipmentSlot::Shield,
            EquipmentSlot::Legs,
            EquipmentSlot::Hands,
            EquipmentSlot::Feet,
            EquipmentSlot::Ring,
            EquipmentSlot::Ammo,
        ]
    }

    /// Convert from EquipSlot (item definition) to EquipmentSlot.
    pub fn from_equip_slot(slot: EquipSlot) -> Option<Self> {
        match slot {
            EquipSlot::Head => Some(EquipmentSlot::Head),
            EquipSlot::Cape => Some(EquipmentSlot::Cape),
            EquipSlot::Amulet => Some(EquipmentSlot::Amulet),
            EquipSlot::Weapon => Some(EquipmentSlot::Weapon),
            EquipSlot::Body => Some(EquipmentSlot::Body),
            EquipSlot::Shield => Some(EquipmentSlot::Shield),
            EquipSlot::Legs => Some(EquipmentSlot::Legs),
            EquipSlot::Hands => Some(EquipmentSlot::Hands),
            EquipSlot::Feet => Some(EquipmentSlot::Feet),
            EquipSlot::Ring => Some(EquipmentSlot::Ring),
            EquipSlot::Ammo => Some(EquipmentSlot::Ammo),
            EquipSlot::None => None,
        }
    }
}

/// Represents equipped item in a slot.
#[derive(Debug, Clone)]
pub struct EquippedItem {
    pub item_id: ItemId,
    pub amount: u32,  // For stackable equipped items like ammo
}

impl EquippedItem {
    pub fn new(item_id: ItemId) -> Self {
        Self { item_id, amount: 1 }
    }

    pub fn new_with_amount(item_id: ItemId, amount: u32) -> Self {
        Self { item_id, amount }
    }
}

/// Player equipment container.
#[derive(Debug, Clone, Default)]
pub struct Equipment {
    slots: HashMap<EquipmentSlot, EquippedItem>,
}

impl Equipment {
    /// Create new empty equipment.
    pub fn new() -> Self {
        Self {
            slots: HashMap::new(),
        }
    }

    /// Get equipped item in a slot.
    pub fn get(&self, slot: EquipmentSlot) -> Option<&EquippedItem> {
        self.slots.get(&slot)
    }

    /// Check if a slot has an item equipped.
    pub fn has_equipped(&self, slot: EquipmentSlot) -> bool {
        self.slots.contains_key(&slot)
    }

    /// Check if a specific item is equipped anywhere.
    pub fn is_wearing(&self, item_id: ItemId) -> bool {
        self.slots.values().any(|e| e.item_id == item_id)
    }

    /// Get the slot where an item is equipped.
    pub fn find_equipped(&self, item_id: ItemId) -> Option<EquipmentSlot> {
        self.slots
            .iter()
            .find(|(_, e)| e.item_id == item_id)
            .map(|(slot, _)| *slot)
    }

    /// Equip an item to a slot.
    /// Returns the previously equipped item, if any.
    pub fn equip(
        &mut self,
        slot: EquipmentSlot,
        item: EquippedItem,
    ) -> Option<EquippedItem> {
        debug!("Equipping item {} to {:?}", item.item_id.0, slot);
        self.slots.insert(slot, item)
    }

    /// Unequip an item from a slot.
    pub fn unequip(&mut self, slot: EquipmentSlot) -> Option<EquippedItem> {
        debug!("Unequipping from {:?}", slot);
        self.slots.remove(&slot)
    }

    /// Get all equipped items.
    pub fn all(&self) -> impl Iterator<Item = (&EquipmentSlot, &EquippedItem)> {
        self.slots.iter()
    }

    /// Get number of equipped items.
    pub fn count(&self) -> usize {
        self.slots.len()
    }

    /// Clear all equipment.
    pub fn clear(&mut self) {
        self.slots.clear();
    }

    /// Calculate total combat bonuses from all equipment.
    pub fn total_bonuses(&self, item_repo: &ItemRepository) -> CombatBonuses {
        let mut total = CombatBonuses::default();

        for equipped in self.slots.values() {
            if let Some(def) = item_repo.get(equipped.item_id) {
                total = total.combine(&def.bonuses);
            }
        }

        total
    }

    /// Get weapon attack speed (in ticks).
    /// Default is 4 ticks if no weapon equipped.
    pub fn weapon_speed(&self, item_repo: &ItemRepository) -> u32 {
        if let Some(weapon) = self.get(EquipmentSlot::Weapon) {
            item_repo
                .get(weapon.item_id)
                .map(|d| d.weapon_speed.unwrap_or(4))
                .unwrap_or(4)
        } else {
            4 // Unarmed attack speed
        }
    }

    /// Check if wearing full set of a specific type.
    pub fn has_full_set(&self, item_ids: &[ItemId]) -> bool {
        item_ids.iter().all(|id| self.is_wearing(*id))
    }
}

/// Equipment validation and management.
pub struct EquipmentManager;

impl EquipmentManager {
    /// Check if a player can equip an item.
    pub fn can_equip(
        item_def: &ItemDef,
        skills: &Skills,
    ) -> Result<(), EquipError> {
        // Check if item is equippable
        if item_def.equip_slot == EquipSlot::None {
            return Err(EquipError::NotEquippable);
        }

        // Check level requirements
        let reqs = &item_def.requirements;

        if skills.get_level(super::skills::SkillType::Attack) < reqs.attack {
            return Err(EquipError::InsufficientLevel {
                skill: "Attack",
                required: reqs.attack,
            });
        }

        if skills.get_level(super::skills::SkillType::Defence) < reqs.defence {
            return Err(EquipError::InsufficientLevel {
                skill: "Defence",
                required: reqs.defence,
            });
        }

        if skills.get_level(super::skills::SkillType::Strength) < reqs.strength {
            return Err(EquipError::InsufficientLevel {
                skill: "Strength",
                required: reqs.strength,
            });
        }

        if skills.get_level(super::skills::SkillType::Ranged) < reqs.ranged {
            return Err(EquipError::InsufficientLevel {
                skill: "Ranged",
                required: reqs.ranged,
            });
        }

        if skills.get_level(super::skills::SkillType::Magic) < reqs.magic {
            return Err(EquipError::InsufficientLevel {
                skill: "Magic",
                required: reqs.magic,
            });
        }

        Ok(())
    }

    /// Equip an item from inventory.
    /// Returns the previously equipped item to add back to inventory.
    pub fn equip_from_inventory(
        equipment: &mut Equipment,
        inventory: &mut Inventory,
        slot: usize,
        item_repo: &ItemRepository,
        skills: &Skills,
    ) -> Result<Option<InventoryItem>, EquipError> {
        let inv_item = inventory.get(slot).ok_or(EquipError::InvalidSlot)?;
        let item_id = inv_item.item_id;

        let item_def = item_repo.get(item_id).ok_or(EquipError::InvalidItem)?;

        // Validate equipment requirements
        Self::can_equip(item_def, skills)?;

        let equip_slot = EquipmentSlot::from_equip_slot(item_def.equip_slot)
            .ok_or(EquipError::NotEquippable)?;

        // Remove from inventory
        let inv_item = inventory.remove_slot(slot).unwrap();

        // Equip and get old item
        let old_equipped = equipment.equip(
            equip_slot,
            EquippedItem::new_with_amount(item_id, inv_item.amount),
        );

        // Convert old equipped item to inventory item
        let old_inv = old_equipped.map(|e| InventoryItem::new(e.item_id, e.amount));

        // Add old item to inventory if present
        if let Some(old) = old_inv.clone() {
            if !inventory.add(old.clone(), item_repo) {
                // This shouldn't happen as we just removed an item
                warn!("Failed to add old equipment to inventory");
            }
        }

        Ok(old_inv)
    }

    /// Unequip an item to inventory.
    pub fn unequip_to_inventory(
        equipment: &mut Equipment,
        inventory: &mut Inventory,
        slot: EquipmentSlot,
        item_repo: &ItemRepository,
    ) -> Result<(), EquipError> {
        if inventory.is_full() {
            return Err(EquipError::InventoryFull);
        }

        let equipped = equipment.unequip(slot).ok_or(EquipError::NotEquipped)?;

        inventory.add(
            InventoryItem::new(equipped.item_id, equipped.amount),
            item_repo,
        );

        Ok(())
    }
}

/// Equipment operation errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EquipError {
    /// Item cannot be equipped.
    NotEquippable,
    /// Insufficient skill level.
    InsufficientLevel {
        skill: &'static str,
        required: u8,
    },
    /// Invalid inventory slot.
    InvalidSlot,
    /// Invalid item ID.
    InvalidItem,
    /// Nothing equipped in that slot.
    NotEquipped,
    /// Inventory is full (cannot unequip).
    InventoryFull,
    /// Item is two-handed but shield is equipped.
    TwoHandedConflict,
}

impl std::fmt::Display for EquipError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            EquipError::NotEquippable => write!(f, "This item cannot be equipped"),
            EquipError::InsufficientLevel { skill, required } => {
                write!(f, "You need {} level {} to equip this", skill, required)
            }
            EquipError::InvalidSlot => write!(f, "Invalid inventory slot"),
            EquipError::InvalidItem => write!(f, "Invalid item"),
            EquipError::NotEquipped => write!(f, "Nothing equipped in that slot"),
            EquipError::InventoryFull => write!(f, "Your inventory is full"),
            EquipError::TwoHandedConflict => {
                write!(f, "You cannot equip a shield with a two-handed weapon")
            }
        }
    }
}

impl std::error::Error for EquipError {}

/// Appearance slot for character model.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AppearanceSlot {
    pub head: Option<ItemId>,
    pub body: Option<ItemId>,
    pub legs: Option<ItemId>,
    pub weapon: Option<ItemId>,
    pub shield: Option<ItemId>,
    pub cape: Option<ItemId>,
    pub amulet: Option<ItemId>,
    pub hands: Option<ItemId>,
    pub feet: Option<ItemId>,
}

impl AppearanceSlot {
    /// Create appearance from equipment.
    pub fn from_equipment(equipment: &Equipment) -> Self {
        Self {
            head: equipment.get(EquipmentSlot::Head).map(|e| e.item_id),
            body: equipment.get(EquipmentSlot::Body).map(|e| e.item_id),
            legs: equipment.get(EquipmentSlot::Legs).map(|e| e.item_id),
            weapon: equipment.get(EquipmentSlot::Weapon).map(|e| e.item_id),
            shield: equipment.get(EquipmentSlot::Shield).map(|e| e.item_id),
            cape: equipment.get(EquipmentSlot::Cape).map(|e| e.item_id),
            amulet: equipment.get(EquipmentSlot::Amulet).map(|e| e.item_id),
            hands: equipment.get(EquipmentSlot::Hands).map(|e| e.item_id),
            feet: equipment.get(EquipmentSlot::Feet).map(|e| e.item_id),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_repo() -> ItemRepository {
        ItemRepository::new()
    }

    #[test]
    fn test_equipment_basic() {
        let mut equipment = Equipment::new();

        let sword = EquippedItem::new(ItemId(1));
        equipment.equip(EquipmentSlot::Weapon, sword);

        assert!(equipment.has_equipped(EquipmentSlot::Weapon));
        assert!(equipment.is_wearing(ItemId(1)));
        assert!(!equipment.has_equipped(EquipmentSlot::Shield));
    }

    #[test]
    fn test_equipment_swap() {
        let mut equipment = Equipment::new();

        let sword1 = EquippedItem::new(ItemId(1));
        let sword2 = EquippedItem::new(ItemId(2));

        equipment.equip(EquipmentSlot::Weapon, sword1);
        let old = equipment.equip(EquipmentSlot::Weapon, sword2);

        assert!(old.is_some());
        assert_eq!(old.unwrap().item_id, ItemId(1));
        assert_eq!(equipment.get(EquipmentSlot::Weapon).unwrap().item_id, ItemId(2));
    }

    #[test]
    fn test_total_bonuses() {
        let repo = test_repo();
        let mut equipment = Equipment::new();

        // Equip bronze sword (id 1)
        equipment.equip(EquipmentSlot::Weapon, EquippedItem::new(ItemId(1)));

        let bonuses = equipment.total_bonuses(&repo);
        // Bronze sword should have some attack bonus
        assert!(bonuses.attack_stab > 0 || bonuses.attack_slash > 0);
    }
}
