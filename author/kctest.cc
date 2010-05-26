#include <kccachedb.h>
#include <assert.h>

using namespace std;
using namespace kyotocabinet;

// main routine
int main(int argc, char** argv) {

  // create the database object
  CacheDB db;

  // open the database
  if (!db.cap_count(10)) {
    cerr << "cap_count error: " << db.error().name() << endl;
  }
  if (!db.open("*", CacheDB::OWRITER | CacheDB::OCREATE)) {
    cerr << "open error: " << db.error().name() << endl;
  }

  // store records
  char buf[1024];
  for (int i=0; i<10000; i++) {
    snprintf(buf, 1024, "%d", i);
    assert(db.set(buf, buf));
  }

  cerr << db.count() << endl;

  // close the database
  if (!db.close()) {
    cerr << "close error: " << db.error().name() << endl;
  }

  return 0;
}
