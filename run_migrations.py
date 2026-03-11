import os
import psycopg2

def run_migrations():
    # Attempt direct connection string for Supabase
    conn_string = "postgresql://postgres:Mobipackaging111!@db.igrudnilqwmlgvmgneng.supabase.co:5432/postgres"
    
    try:
        conn = psycopg2.connect(conn_string)
        conn.autocommit = True
        cur = conn.cursor()
        print("Connected to Supabase via direct connection!")
        
        with open("infra/supabase/migrations/040_trips_system.sql", "r") as f:
            sql040 = f.read()
            print("Running 040_trips_system.sql...")
            cur.execute(sql040)
            print("Successfully applied 040_trips_system.sql")
            
        with open("infra/supabase/migrations/041_fix_timeline_km.sql", "r") as f:
            sql041 = f.read()
            print("Running 041_fix_timeline_km.sql...")
            cur.execute(sql041)
            print("Successfully applied 041_fix_timeline_km.sql")
            
        cur.close()
        conn.close()
        print("Migrations complete.")
    except Exception as e:
        print(f"Error executing migrations: {e}")

if __name__ == "__main__":
    run_migrations()
