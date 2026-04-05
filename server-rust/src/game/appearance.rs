//! Player appearance system.
//! Handles character appearance data, validation, and appearance update packet encoding
//! matching the Java server's GameStateUpdater type 5 format.

use super::equipment::{Equipment, EquipmentSlot};

/// Player appearance configuration.
#[derive(Debug, Clone)]
pub struct PlayerAppearance {
    pub hair_color: u8,
    pub top_color: u8,
    pub trouser_color: u8,
    pub skin_color: u8,
    pub head_sprite: u8,
    pub body_sprite: u8,
    pub is_male: bool,
    pub skull_type: u8,
    pub combat_level: u32,
    pub clan_tag: Option<String>,
    pub is_invisible: bool,
    pub is_invulnerable: bool,
}

impl Default for PlayerAppearance {
    fn default() -> Self {
        Self {
            hair_color: 2,
            top_color: 8,
            trouser_color: 14,
            skin_color: 0,
            head_sprite: 1,
            body_sprite: 2,
            is_male: true,
            skull_type: 0,
            combat_level: 3,
            clan_tag: None,
            is_invisible: false,
            is_invulnerable: false,
        }
    }
}

/// Appearance validation error.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AppearanceError {
    InvalidHairColor(u8),
    InvalidTopColor(u8),
    InvalidTrouserColor(u8),
    InvalidSkinColor(u8),
    InvalidHeadSprite(u8),
    InvalidBodySprite(u8),
    InvalidSkullType(u8),
    ClanTagTooLong(usize),
}

impl std::fmt::Display for AppearanceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AppearanceError::InvalidHairColor(v) => write!(f, "Hair color {} out of range 0-9", v),
            AppearanceError::InvalidTopColor(v) => write!(f, "Top color {} out of range 0-14", v),
            AppearanceError::InvalidTrouserColor(v) => {
                write!(f, "Trouser color {} out of range 0-14", v)
            }
            AppearanceError::InvalidSkinColor(v) => {
                write!(f, "Skin color {} out of range 0-4", v)
            }
            AppearanceError::InvalidHeadSprite(v) => {
                write!(f, "Head sprite {} is not a valid type", v)
            }
            AppearanceError::InvalidBodySprite(v) => {
                write!(f, "Body sprite {} is not a valid type", v)
            }
            AppearanceError::InvalidSkullType(v) => {
                write!(f, "Skull type {} out of range 0-1", v)
            }
            AppearanceError::ClanTagTooLong(len) => {
                write!(f, "Clan tag length {} exceeds max 16", len)
            }
        }
    }
}

impl std::error::Error for AppearanceError {}

/// Valid head sprites: 1=male default, 4=female default, 6/7=variant heads.
const VALID_HEAD_SPRITES: &[u8] = &[1, 4, 6, 7];

/// Valid body sprites: 2=male default, 5=female default.
const VALID_BODY_SPRITES: &[u8] = &[2, 5];

const MAX_HAIR_COLOR: u8 = 9;
const MAX_BODY_COLOR: u8 = 14;
const MAX_SKIN_COLOR: u8 = 4;
const MAX_CLAN_TAG_LEN: usize = 16;

impl PlayerAppearance {
    /// Create a new male appearance with default colors.
    pub fn new_male() -> Self {
        Self::default()
    }

    /// Create a new female appearance with default colors.
    pub fn new_female() -> Self {
        Self {
            head_sprite: 4,
            body_sprite: 5,
            is_male: false,
            ..Self::default()
        }
    }

    /// Validate all appearance values are within allowed ranges.
    pub fn validate(&self) -> Result<(), AppearanceError> {
        if self.hair_color > MAX_HAIR_COLOR {
            return Err(AppearanceError::InvalidHairColor(self.hair_color));
        }
        if self.top_color > MAX_BODY_COLOR {
            return Err(AppearanceError::InvalidTopColor(self.top_color));
        }
        if self.trouser_color > MAX_BODY_COLOR {
            return Err(AppearanceError::InvalidTrouserColor(self.trouser_color));
        }
        if self.skin_color > MAX_SKIN_COLOR {
            return Err(AppearanceError::InvalidSkinColor(self.skin_color));
        }
        if !VALID_HEAD_SPRITES.contains(&self.head_sprite) {
            return Err(AppearanceError::InvalidHeadSprite(self.head_sprite));
        }
        if !VALID_BODY_SPRITES.contains(&self.body_sprite) {
            return Err(AppearanceError::InvalidBodySprite(self.body_sprite));
        }
        if self.skull_type > 1 {
            return Err(AppearanceError::InvalidSkullType(self.skull_type));
        }
        if let Some(ref tag) = self.clan_tag {
            if tag.len() > MAX_CLAN_TAG_LEN {
                return Err(AppearanceError::ClanTagTooLong(tag.len()));
            }
        }
        Ok(())
    }

    /// Set gender and update head/body sprites to match.
    pub fn set_gender(&mut self, male: bool) {
        self.is_male = male;
        if male {
            self.head_sprite = 1;
            self.body_sprite = 2;
        } else {
            self.head_sprite = 4;
            self.body_sprite = 5;
        }
    }
}

/// Build the appearance data byte sequence for the player update packet.
/// Matches the Java server's GameStateUpdater type 5 encoding.
///
/// Wire format:
///   string  username (null-terminated)
///   byte    equipped item count
///   per equipped item: short worn_item_id
///   byte    hair_color
///   byte    top_color
///   byte    trouser_color
///   byte    skin_color
///   byte    combat_level
///   byte    skull_type
///   byte    has_clan (1/0), [string clan_tag if 1]
///   byte    is_invisible (1/0)
///   byte    is_invulnerable (1/0)
///   byte    group_id (staff rank)
///   int     icon
pub fn build_appearance_data(
    username: &str,
    appearance: &PlayerAppearance,
    equipment: &Equipment,
    group_id: u8,
    icon: u32,
) -> Vec<u8> {
    let mut buf: Vec<u8> = Vec::with_capacity(64);

    // Username (null-terminated string)
    buf.extend_from_slice(username.as_bytes());
    buf.push(0);

    // Collect worn item IDs from equipment
    let worn_items = collect_worn_items(equipment);
    buf.push(worn_items.len() as u8);
    for item_id in &worn_items {
        buf.push((*item_id >> 8) as u8);
        buf.push(*item_id as u8);
    }

    // Color and sprite data
    buf.push(appearance.hair_color);
    buf.push(appearance.top_color);
    buf.push(appearance.trouser_color);
    buf.push(appearance.skin_color);

    // Combat and status
    buf.push(appearance.combat_level.min(255) as u8);
    buf.push(appearance.skull_type);

    // Clan tag
    match &appearance.clan_tag {
        Some(tag) => {
            buf.push(1);
            buf.extend_from_slice(tag.as_bytes());
            buf.push(0);
        }
        None => {
            buf.push(0);
        }
    }

    // Status flags
    buf.push(u8::from(appearance.is_invisible));
    buf.push(u8::from(appearance.is_invulnerable));

    // Staff rank and icon
    buf.push(group_id);
    buf.push((icon >> 24) as u8);
    buf.push((icon >> 16) as u8);
    buf.push((icon >> 8) as u8);
    buf.push(icon as u8);

    buf
}

/// Collect worn item IDs from equipment in slot order.
fn collect_worn_items(equipment: &Equipment) -> Vec<u16> {
    let slot_order = [
        EquipmentSlot::Head,
        EquipmentSlot::Cape,
        EquipmentSlot::Amulet,
        EquipmentSlot::Weapon,
        EquipmentSlot::Body,
        EquipmentSlot::Shield,
        EquipmentSlot::Legs,
        EquipmentSlot::Hands,
        EquipmentSlot::Feet,
    ];

    slot_order
        .iter()
        .filter_map(|slot| equipment.get(*slot).map(|e| e.item_id.0 as u16))
        .collect()
}

/// Character creation screen configuration.
/// Provides the available options presented during new player creation.
pub struct AppearanceScreen;

impl AppearanceScreen {
    /// Number of available hair colors (indices 0..=9).
    pub const HAIR_COLOR_COUNT: u8 = 10;

    /// Number of available body/top colors (indices 0..=14).
    pub const BODY_COLOR_COUNT: u8 = 15;

    /// Number of available skin colors (indices 0..=4).
    pub const SKIN_COLOR_COUNT: u8 = 5;

    /// Build a default appearance from character creation selections.
    pub fn create(male: bool, hair_color: u8, top_color: u8, trouser_color: u8, skin_color: u8) -> PlayerAppearance {
        let mut appearance = if male {
            PlayerAppearance::new_male()
        } else {
            PlayerAppearance::new_female()
        };
        appearance.hair_color = hair_color;
        appearance.top_color = top_color;
        appearance.trouser_color = trouser_color;
        appearance.skin_color = skin_color;
        appearance
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_appearance_valid() {
        let appearance = PlayerAppearance::default();
        assert!(appearance.validate().is_ok());
        assert!(appearance.is_male);
    }

    #[test]
    fn test_female_appearance_valid() {
        let appearance = PlayerAppearance::new_female();
        assert!(appearance.validate().is_ok());
        assert!(!appearance.is_male);
        assert_eq!(appearance.head_sprite, 4);
        assert_eq!(appearance.body_sprite, 5);
    }

    #[test]
    fn test_validation_rejects_out_of_range() {
        let mut a = PlayerAppearance::default();
        a.hair_color = 20;
        assert!(matches!(a.validate(), Err(AppearanceError::InvalidHairColor(20))));

        let mut a = PlayerAppearance::default();
        a.skin_color = 10;
        assert!(matches!(a.validate(), Err(AppearanceError::InvalidSkinColor(10))));

        let mut a = PlayerAppearance::default();
        a.head_sprite = 99;
        assert!(matches!(a.validate(), Err(AppearanceError::InvalidHeadSprite(99))));
    }

    #[test]
    fn test_build_appearance_data_basic() {
        let appearance = PlayerAppearance::default();
        let equipment = Equipment::new();
        let data = build_appearance_data("testuser", &appearance, &equipment, 0, 0);

        // Username "testuser" + null terminator = 9 bytes
        assert_eq!(data[8], 0); // null terminator
        // 0 equipped items
        assert_eq!(data[9], 0);
        // Colors at offset 10..14
        assert_eq!(data[10], 2);  // hair_color
        assert_eq!(data[11], 8);  // top_color
        assert_eq!(data[12], 14); // trouser_color
        assert_eq!(data[13], 0);  // skin_color
    }

    #[test]
    fn test_set_gender() {
        let mut a = PlayerAppearance::default();
        a.set_gender(false);
        assert!(!a.is_male);
        assert_eq!(a.head_sprite, 4);
        assert_eq!(a.body_sprite, 5);

        a.set_gender(true);
        assert!(a.is_male);
        assert_eq!(a.head_sprite, 1);
        assert_eq!(a.body_sprite, 2);
    }

    #[test]
    fn test_appearance_screen_create() {
        let a = AppearanceScreen::create(true, 3, 5, 10, 2);
        assert!(a.validate().is_ok());
        assert_eq!(a.hair_color, 3);
        assert_eq!(a.top_color, 5);
        assert_eq!(a.trouser_color, 10);
        assert_eq!(a.skin_color, 2);
    }
}
