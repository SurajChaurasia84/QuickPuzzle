# Keep WorkManager and its internal database implementation
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class * extends androidx.work.Worker { *; }

# Keep Room database and generated implementation classes (WorkDatabase is built on Room)
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class * extends androidx.room.RoomDatabase$* { *; }
-keep class * extends androidx.room.RoomOpenHelper { *; }
-keep class * extends androidx.room.migration.Migration { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-dontwarn androidx.room.paging.**
