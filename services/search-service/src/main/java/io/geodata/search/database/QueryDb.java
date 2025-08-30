package io.geodata.search.database;

import io.geodata.search.*;
import io.geodata.search.model.*;
import java.util.*;


public interface QueryDb {

      List<ItemOut> query(StacFilter filter);
}