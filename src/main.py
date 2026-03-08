# ----------- main.py -----------
from nlib import porche, Status  # import แค่ porche object และ enum ที่ต้องการ

def test_oche():
    print("--- 1. Basic Function Call (Strings) ---")
    greeting = porche.greetPy("Gemini")
    print(f"Result: {greeting}")
    print()

    print("--- 2. Struct Unpacking (User) ---")
    # createUserPy จะคืนค่าเป็น Dict ตามที่ _struct_from_ctypes นิยามไว้
    user = porche.createUserPy("Bleamz", 44)
    if user:
        print(f"User created: {user}")
        # เข้าถึงข้อมูลผ่าน Key เพราะมันคือ Dict
        # หมายเหตุ: 'username' และ 'primaryTag' ใน nlib.py ตอนนี้เป็น c_void_p 
        # ถ้าจะอ่านค่าข้างใน อาจจะต้องพึ่งพา getter หรือปรับ emitter เพิ่มเติม
    print()

    print("--- 3. List of Structs (Points Copy) ---")
    points = porche.getPointsCopyPy(3)
    print(f"Points received (List): {len(points)}")
    for i, p in enumerate(points):
        print(f"  Point[{i}]: {p}")
    print()

    print("--- 4. Shared Live Buffer (Users) ---")
    # initSharedUsersPy คืนค่าเป็น _SharedView object
    shared_users = porche.initSharedUsersPy(2)
    print(f"Shared users buffer length: {len(shared_users)}")
    
    if len(shared_users) > 0:
        # ลองอ่านค่าตัวแรก
        print(f"Initial User[0]: {shared_users[0]}")
        
        # ลองเขียนค่ากลับ (__setitem__ จะทำงาน)
        # porche จะจัดการ _ocheFreeInner ให้โดยอัตโนมัติถ้าไม่ใช่ POD
        try:
            shared_users[0] = {'username': None, 'status': Status.Active, 'primaryTag': None}
            print("Successfully updated SharedUser[0]")
        except Exception as e:
            print(f"Update failed: {e}")

    print("\n--- 5. NumPy Integration (Optional) ---")
    points_shared = porche.initSharedUsersPy(5) # สมมติว่าต้องการดู buffer ในรูปแบบ numpy
    arr = points_shared.to_numpy()
    if arr is not None:
        print(f"NumPy array created! Shape: {arr.shape}")
    else:
        print("NumPy not available or not supported for this type.")

if __name__ == "__main__":
    test_oche()