import pub_alias_total
import pub_alias_reexport
import pub_alias_source

fn parent_item_from_alias(value int) pub_alias_total.Item {
	return pub_alias_total.make_alias_item(value)
}

fn alias_item_from_parent(value int) pub_alias_total.ItemAlias {
	return pub_alias_total.Item{
		value: value
	}
}

fn parent_list_from_alias() []pub_alias_total.Item {
	return pub_alias_total.make_item_list()
}

fn alias_list_from_parent(items []pub_alias_total.Item) pub_alias_total.ItemList {
	return items
}

fn takes_parent_list(items []pub_alias_total.Item) int {
	mut sum := 0
	for item in items {
		sum += item.value
	}
	return sum
}

fn takes_alias_list(items pub_alias_total.ItemList) int {
	mut sum := 0
	for item in items {
		sum += item.value
	}
	return sum
}

fn test_pub_alias_item_return_cross_module() {
	assert parent_item_from_alias(3).value == 3
	assert alias_item_from_parent(4).value == 4
}

fn test_pub_alias_array_return_cross_module() {
	items := parent_list_from_alias()
	assert items.len == 2
	assert takes_parent_list(pub_alias_total.make_item_list()) == 3
	assert takes_alias_list(items) == 3
	assert takes_parent_list(pub_alias_total.alias_list_from_parent(items)) == 3
	assert takes_alias_list(alias_list_from_parent(items)) == 3
}

fn source_item_from_public(value int) pub_alias_source.SourceItem {
	return pub_alias_reexport.make_public_item(value)
}

fn public_item_from_source(value int) pub_alias_reexport.PublicItem {
	return pub_alias_source.make_source_item(value)
}

fn source_items_from_public() []pub_alias_source.SourceItem {
	return pub_alias_reexport.make_public_items()
}

fn public_items_from_source() pub_alias_reexport.PublicItems {
	return pub_alias_source.make_source_items()
}

fn direct_public_array_from_source() []pub_alias_reexport.PublicItem {
	return pub_alias_source.make_source_items()
}

fn direct_source_array_from_public(items []pub_alias_reexport.PublicItem) []pub_alias_source.SourceItem {
	return items
}

fn takes_source_items(items []pub_alias_source.SourceItem) int {
	mut sum := 0
	for item in items {
		sum += item.value
	}
	return sum
}

fn takes_public_items(items pub_alias_reexport.PublicItems) int {
	mut sum := 0
	for item in items {
		sum += item.value
	}
	return sum
}

fn test_pub_reexport_alias_item_return_cross_module() {
	assert source_item_from_public(6).value == 6
	assert public_item_from_source(7).value == 7
}

fn test_pub_reexport_alias_array_return_cross_module() {
	items := pub_alias_reexport.make_public_items()
	assert source_items_from_public().len == 2
	assert public_items_from_source().len == 2
	assert direct_public_array_from_source().len == 2
	assert direct_source_array_from_public(direct_public_array_from_source()).len == 2
	assert takes_source_items(items) == 13
	assert takes_public_items(pub_alias_source.make_source_items()) == 13
	assert takes_source_items(direct_public_array_from_source()) == 13
}
