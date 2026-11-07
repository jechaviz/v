module pub_alias_source

pub struct SourceItem {
pub:
	value int
}

pub fn make_source_item(value int) SourceItem {
	return SourceItem{
		value: value
	}
}

pub fn make_source_items() []SourceItem {
	return [SourceItem{
		value: 5
	}, SourceItem{
		value: 8
	}]
}
