package com.openrsc.server.database.builder;

import java.util.LinkedHashMap;
import java.util.Map;

public class TableBuilder {
	private final String tableName;
	private String tableContents;
	private final Map<String, String> tableProperties;

	public TableBuilder(String tableName) {
		this(tableName, new LinkedHashMap<>());
	}

	public TableBuilder(String tableName, Map<String, String> tableProperties) {
		this.tableName = tableName;
		this.tableProperties = tableProperties;
		this.tableContents = "";
	}

	public TableBuilder addColumn(String columnName, String columnDescriptor) {
		if (!columnName.trim().isEmpty() && !columnDescriptor.trim().isEmpty()) {
			this.tableContents += "`%s` %s,\n".formatted(columnName, columnDescriptor);
		}
		return this;
	}

	public TableBuilder addPrimaryKey(String primaryKey) {
		if (!primaryKey.trim().isEmpty()) {
			this.tableContents += "PRIMARY KEY (`%s`),\n".formatted(primaryKey);
		}
		return this;
	}

	public TableBuilder addKey(String key, String refKey) {
		if (!key.trim().isEmpty() && !refKey.trim().isEmpty()) {
			this.tableContents += "KEY `%s` (`%s`),\n".formatted(key, refKey);
		}
		return this;
	}

	@Override
	public String toString() {
		var propsAsString = new StringBuilder();
		for (var entry : tableProperties.entrySet()) {
			propsAsString.append("%s = %s\n".formatted(entry.getKey(), entry.getValue()));
		}
		int indexLastComma = this.tableContents.lastIndexOf(",");
		return "CREATE TABLE `%s`\n(\n%s\n) %s".formatted(
			this.tableName,
			this.tableContents.substring(0, indexLastComma),
			propsAsString
		);
	}
}
