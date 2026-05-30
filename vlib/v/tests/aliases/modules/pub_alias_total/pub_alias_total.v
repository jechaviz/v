module pub_alias_total

pub struct Item {
pub:
	value int
}

pub type ItemAlias = Item
pub type ItemList = []Item

pub fn make_alias_item(value int) ItemAlias {
	return Item{
		value: value
	}
}

pub fn make_item_list() ItemList {
	return [Item{
		value: 1
	}, Item{
		value: 2
	}]
}

pub fn make_parent_list() []Item {
	return make_item_list()
}

pub fn alias_list_from_parent(items []Item) ItemList {
	return items
}
