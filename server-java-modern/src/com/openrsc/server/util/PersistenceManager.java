package com.openrsc.server.util;

import com.openrsc.server.Server;
import com.thoughtworks.xstream.XStream;
import com.thoughtworks.xstream.security.NoTypePermission;
import com.thoughtworks.xstream.security.NullPermission;
import com.thoughtworks.xstream.security.PrimitiveTypePermission;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.io.*;
import java.util.Enumeration;
import java.util.Properties;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

public final class PersistenceManager {

	/**
	 * The asynchronous logger.
	 */
	private static final Logger LOGGER = LogManager.getLogger("OpenRSC");

	private static final XStream xstream = new XStream();

	private final Server server;

	public PersistenceManager(Server server) {
		this.server = server;
		// Restrict deserialization instead of the blanket AnyTypePermission.ANY
		// (which re-enables XStream gadget-chain RCE). Permit nulls/primitives/
		// String, this project's own types, and the standard collection/map
		// hierarchies. Each type declared in aliases.xml is additionally
		// allow-listed as it is registered in setupAliases().
		xstream.addPermission(NoTypePermission.NONE);
		xstream.addPermission(NullPermission.NULL);
		xstream.addPermission(PrimitiveTypePermission.PRIMITIVES);
		xstream.allowTypeHierarchy(String.class);
		xstream.allowTypeHierarchy(java.util.Collection.class);
		xstream.allowTypeHierarchy(java.util.Map.class);
		xstream.allowTypesByWildcard(new String[]{"com.openrsc.**"});
		setupAliases();
	}

	public Object load(String filename) {
		try {
			File theFile = new File(getServer().getConfig().CONFIG_DIR, filename);
			boolean isGzipped = false;
			if (!theFile.exists()) {
				// fallback for old servers using .gz definitions
				theFile = new File(getServer().getConfig().CONFIG_DIR, filename + ".gz");
				isGzipped = true;
			}
			InputStream is = new FileInputStream(theFile);
			if (isGzipped) {
				is = new GZIPInputStream(is);
			}
			Object rv = xstream.fromXML(is);
			return rv;
		} catch (IOException ioe) {
			LOGGER.catching(ioe);
		}
		return null;
	}

	protected void setupAliases() {
		try {
			Properties aliases = new Properties();
			FileInputStream fis = new FileInputStream(new File(getServer().getConfig().CONFIG_DIR, "aliases.xml"));
			aliases.loadFromXML(fis);
			for (Enumeration<?> e = aliases.propertyNames(); e.hasMoreElements(); ) {
				String alias = (String) e.nextElement();
				Class<?> c = Class.forName((String) aliases.get(alias));
				// Permit exactly the classes declared in aliases.xml, so any
				// type outside the app package that is intentionally aliased is
				// still deserializable while arbitrary gadget types are not.
				xstream.allowTypes(new Class[]{c});
				xstream.alias(alias, c);
			}
		} catch (Exception ioe) {
			LOGGER.catching(ioe);
		}
	}

	public void write(String filename, Object o) {
		try {
			OutputStream os = new FileOutputStream(new File(getServer().getConfig().CONFIG_DIR, filename));
			if (filename.endsWith(".gz")) {
				os = new GZIPOutputStream(os);
			}
			xstream.toXML(o, os);
		} catch (IOException ioe) {
			LOGGER.catching(ioe);
		}
	}

	public Server getServer() {
		return server;
	}
}
