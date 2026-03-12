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
        
        with open("infra/supabase/migrations/20260311185257_fix_item_categories.sql", "r") as f:
            sql = f.read()
            print("Running 20260311185257_fix_item_categories.sql...")
            cur.execute(sql)
            print("Successfully applied 20260311185257_fix_item_categories.sql")
            
        cur.close()
        conn.close()
        print("Migrations complete.")
    except Exception as e:
        print(f"Error executing migrations: {e}")

if __name__ == "__main__":
    run_migrations()
