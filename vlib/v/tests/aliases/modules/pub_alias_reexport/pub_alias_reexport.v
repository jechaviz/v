module pub_alias_reexport

import pub_alias_source

pub type PublicItem = pub_alias_source.SourceItem
pub type PublicItems = []PublicItem

pub fn make_public_item(value int) PublicItem {
	return pub_alias_source.make_source_item(value)
}

pub fn make_public_items() PublicItems {
	return pub_alias_source.make_source_items()
}

pub fn make_source_items() []pub_alias_source.SourceItem {
	return make_public_items()
}
