// ===== BRANDO FURNITURE — App Logic =====

// --- Sample Products (User will add their own) ---
let products = [];
async function fetchProducts() {
    try {
        // --- NEW: Firebase Logic ---
        if (window.db) {
            const snapshot = await window.db.collection('products').get();
            products = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
            console.log("Loaded from Firebase:", products.length);
        } else {
            // Local Fallback (Development or Static)
            const response = await fetch(`products.json?t=${Date.now()}`);
            products = await response.json();
        }

        if (!products || products.length === 0) products = [];

        renderProducts();
        // Update category counts after products are loaded
        fetchCategories();
    } catch (err) {
        console.error('Failed to fetch products:', err);
    }
}

// --- Categories ---
// --- New: Dynamic Categories ---
let categories = [];
async function fetchCategories() {
    try {
        if (window.db) {
            const snapshot = await window.db.collection('categories').get();
            categories = snapshot.docs.map(doc => doc.data());
            console.log("Loaded categories from Firebase:", categories.length);
        } else {
            const response = await fetch(`categories.json?t=${Date.now()}`);
            categories = await response.json();
        }
        
        if (!categories || categories.length === 0) throw new Error("No categories");

        // Update category counts based on current products
        categories.forEach(c => {
            c.count = products.filter(p => p.category && p.category.toLowerCase() === c.name.toLowerCase()).length;
        });
        renderCategories();
        renderFilters();
    } catch (err) {
        console.error('Failed to fetch categories:', err);
        // Fallback for safety
        categories = [
            { name: "Wall Decors", image: "https://images.unsplash.com/photo-1513519245088-0e12902e5a38?auto=format&fit=crop&q=80&w=600", count: 0 },
            { name: "Frames", image: "https://images.unsplash.com/photo-1544457070-4cd773b4d71e?auto=format&fit=crop&q=80&w=600", count: 0 },
            { name: "Statues", image: "https://images.unsplash.com/photo-1601758124277-2850906b3be3?auto=format&fit=crop&q=80&w=600", count: 0 },
            { name: "Clocks", image: "https://images.unsplash.com/photo-1563861826-1fb1b0a91a9e?auto=format&fit=crop&q=80&w=600", count: 0 }
        ];
        renderCategories();
        renderFilters();
    }
}

// --- State ---
let cart = [];
let currentFilter = 'All';

// --- Format Currency ---
const formatPrice = (price) => new Intl.NumberFormat('en-IN', {
    style: 'currency', currency: 'INR', maximumFractionDigits: 0
}).format(price);

// --- DOM ---
const productGrid = document.getElementById('product-grid');
const cartBadge = document.getElementById('cart-badge');
const cartItemsEl = document.getElementById('cart-items');
const cartTotalEl = document.getElementById('cart-total');
const cartSidebar = document.getElementById('cart-sidebar');
const cartOverlay = document.getElementById('cart-overlay');
const toast = document.getElementById('toast');

// --- Render Categories ---
function renderCategories() {
    const grid = document.getElementById('categories-grid');
    grid.innerHTML = categories.map(cat => `
        <div class="category-card" onclick="filterProducts('${cat.name}')">
            <img src="${cat.image}" alt="${cat.name}">
            <div class="cat-overlay">
                <h3>${cat.name}</h3>
                <span>${cat.count} Products</span>
            </div>
        </div>
    `).join('');
}

// --- Render Filter Buttons ---
function renderFilters() {
    const filtersEl = document.getElementById('product-filters');
    const cats = ['All', ...categories.map(c => c.name)];
    filtersEl.innerHTML = cats.map(c => `
        <button class="filter-btn ${c === currentFilter ? 'active' : ''}" onclick="filterProducts('${c}')">${c}</button>
    `).join('');
}

// --- Render Products ---
function renderProducts(list = products) {
    if (list.length === 0) {
        productGrid.innerHTML = `
            <div class="no-products">
                <ion-icon name="search-outline"></ion-icon>
                <p>No products found</p>
            </div>`;
        return;
    }
    productGrid.innerHTML = list.map((p, i) => `
        <div class="product-card fade-up" style="animation-delay:${i * 50}ms">
            <div class="product-img">
                <img src="${p.image}" alt="${p.name}">
                <div class="product-tag">${p.category}</div>
            </div>
            <div class="product-body">
                <h3>${p.name}</h3>
                <p class="product-desc">${p.description}</p>
                <div class="product-footer">
                    <span class="product-price">${formatPrice(p.price)}</span>
                    <button class="add-cart-btn" onclick="addToCart('${p.id}')" aria-label="Add to cart">
                        <ion-icon name="cart-outline"></ion-icon>
                    </button>
                </div>
            </div>
        </div>
    `).join('');
    // Re-observe fade-up elements
    document.querySelectorAll('.product-card.fade-up').forEach(el => observer.observe(el));
}

// --- Filter ---
function filterProducts(cat) {
    currentFilter = cat;
    renderFilters();
    const filtered = cat === 'All' ? products : products.filter(p => p.category && p.category.toLowerCase() === cat.toLowerCase());
    renderProducts(filtered);
    document.getElementById('shop').scrollIntoView({ behavior: 'smooth' });
}

// --- Search ---
function handleSearch() {
    const q = document.getElementById('search-input').value.toLowerCase();
    if (!q) { renderProducts(); return; }
    const filtered = products.filter(p =>
        p.name.toLowerCase().includes(q) || p.category.toLowerCase().includes(q) || p.description.toLowerCase().includes(q)
    );
    renderProducts(filtered);
}

function toggleSearch() {
    const bar = document.getElementById('search-bar');
    bar.classList.toggle('hidden');
    if (!bar.classList.contains('hidden')) {
        document.getElementById('search-input').focus();
    }
}

// --- Cart ---
function addToCart(id) {
    const product = products.find(p => p.id === id);
    const existing = cart.find(i => i.id === id);
    if (existing) { existing.quantity++; }
    else { cart.push({ ...product, quantity: 1 }); }
    renderCart();
    showToast();
}

function updateQty(id, change) {
    const idx = cart.findIndex(i => i.id === id);
    if (idx > -1) {
        cart[idx].quantity += change;
        if (cart[idx].quantity <= 0) cart.splice(idx, 1);
        renderCart();
    }
}

function renderCart() {
    if (cart.length === 0) {
        cartItemsEl.innerHTML = `
            <div class="empty-cart">
                <ion-icon name="cart-outline"></ion-icon>
                <p>Your cart is empty</p>
                <button onclick="toggleCart(); showShop();" class="btn btn-gold-sm">Start Shopping</button>
            </div>`;
        document.getElementById('cart-footer').style.display = 'none';
        document.getElementById('checkout-form').classList.add('hidden');
    } else {
        cartItemsEl.innerHTML = `<div>${cart.map(item => `
            <div class="cart-item-row">
                <div class="cart-item-img"><img src="${item.image}" alt="${item.name}"></div>
                <div class="cart-item-info">
                    <h4>${item.name}</h4>
                    <span class="ci-price">${formatPrice(item.price)}</span>
                </div>
                <div class="cart-item-qty">
                    <button onclick="updateQty('${item.id}', -1)"><ion-icon name="remove-outline"></ion-icon></button>
                    <span>${item.quantity}</span>
                    <button onclick="updateQty('${item.id}', 1)"><ion-icon name="add-outline"></ion-icon></button>
                </div>
            </div>
        `).join('')}</div>`;
        document.getElementById('cart-footer').style.display = 'block';
        document.getElementById('checkout-form').classList.remove('hidden');
    }
    const total = cart.reduce((s, i) => s + (Number(i.price) || 0) * i.quantity, 0);
    cartTotalEl.textContent = formatPrice(total);
    const count = cart.reduce((s, i) => s + i.quantity, 0);
    cartBadge.textContent = count;
    cartBadge.classList.toggle('scale-0', count === 0);
    cartBadge.classList.toggle('scale-100', count > 0);
    
    // Update UPI QR Total display
    if (document.getElementById('upi-total-display')) {
        document.getElementById('upi-total-display').textContent = formatPrice(total);
        const upiUrl = `upi://pay?pa=brandofurniture23@okicici&pn=Brando%20Furniture&am=${total}&cu=INR`;
        document.getElementById('qr-img').src = `https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${encodeURIComponent(upiUrl)}`;
        document.getElementById('upi-pay-btn').onclick = () => window.location.href = upiUrl;
    }
}

function toggleCart() {
    const open = !cartSidebar.classList.contains('translate-x-full');
    if (open) {
        cartSidebar.classList.add('translate-x-full');
        cartOverlay.classList.remove('opacity-100');
        setTimeout(() => cartOverlay.classList.add('hidden'), 300);
    } else {
        cartOverlay.classList.remove('hidden');
        void cartOverlay.offsetWidth;
        cartOverlay.classList.add('opacity-100');
        cartSidebar.classList.remove('translate-x-full');
    }
}

// --- Checkout ---

function toggleUPIDisplay(show) {
    const upiSection = document.getElementById('upi-qr-section');
    const btnText = document.getElementById('btn-text');
    if (!upiSection || !btnText) return;
    if (show) {
        upiSection.classList.remove('hidden');
        btnText.innerText = "Pay & Place Order";
    } else {
        upiSection.classList.add('hidden');
        btnText.innerText = "Place Order";
    }
}

function placeOrder() {
    try {
    const name = document.getElementById('co-name').value.trim();
    const mobile = document.getElementById('co-mobile').value.trim();
    const address = document.getElementById('co-address').value.trim();
    const landmark = document.getElementById('co-landmark').value.trim();
    const pincode = document.getElementById('co-pincode').value.trim();
    const city = document.getElementById('co-city').value.trim();
    const state = document.getElementById('co-state').value;
    const payEl = document.querySelector('input[name="pay"]:checked');
    const pay = payEl ? payEl.value : 'COD';

    if (!name) { alert('Please enter your name'); return; }
    if (!mobile || mobile.length < 10) { alert('Please enter valid mobile number'); return; }
    if (!address) { alert('Please enter street address'); return; }
    if (!pincode || pincode.length < 6) { alert('Please enter 6-digit pin code'); return; }
    if (!city) { alert('Please enter your city'); return; }
    if (!state) { alert('Please select your state'); return; }

    let utr = "";
    if (pay === 'UPI') {
        utr = document.getElementById('co-utr').value.trim();
        if (!utr || utr.length < 4) {
            alert('Payment Verification Required:\nPlease tap "Open GPay / PhonePe", complete your payment, and then type the Transaction/UTR ID here to finish your order.');
            return;
        }
    }

    const total = cart.reduce((s, i) => s + (Number(i.price) || 0) * i.quantity, 0);
    const order = {
        id: 'BRD-' + Date.now(),
        date: new Date().toLocaleString('en-IN'),
        customer: { name, mobile, address, landmark, pincode, city, state },
        paymentMethod: pay === 'UPI' ? 'UPI (UTR: ' + utr + ')' : 'COD',
        items: cart.map(i => ({ name: i.name, category: i.category, price: i.price, quantity: i.quantity, image: i.image })),
        total, status: pay === 'UPI' ? 'Payment Successful' : 'Pending'
    };

    // --- NEW: Firebase Logic ---
    if (window.db) {
        window.db.collection('orders').doc(order.id).set(order)
            .then(() => console.log("Order synced to Cloud"))
            .catch(err => console.error("Cloud sync failed:", err));
    } else {
        fetch('/api/orders', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(order) })
            .catch(err => console.error('Sync failed:', err));
    }

    const orders = JSON.parse(localStorage.getItem('brando_orders') || '[]');
    orders.unshift(order);
    localStorage.setItem('brando_orders', JSON.stringify(orders));

    cart = [];
    renderCart();
    
    // Clear the form fields
    document.getElementById('co-name').value = '';
    document.getElementById('co-mobile').value = '';
    document.getElementById('co-address').value = '';
    document.getElementById('co-landmark').value = '';
    document.getElementById('co-pincode').value = '';
    document.getElementById('co-city').value = '';
    document.getElementById('co-utr').value = '';
    
    // Show success message inside the cart
    cartItemsEl.innerHTML = `
        <div class="empty-cart" style="margin-top: 50px;">
            <div style="width:64px;height:64px;background:#dcfce7;border-radius:50%;display:flex;align-items:center;justify-content:center;margin-bottom:16px">
                <ion-icon name="checkmark-circle" style="font-size:2rem;color:#22c55e"></ion-icon>
            </div>
            <h3 style="font-family:var(--font-display);font-size:1.3rem;margin-bottom:4px">Order Placed! 🎉</h3>
            <p style="font-size:0.82rem;color:var(--text-light);margin-bottom:4px">ID: <strong>${order.id}</strong></p>
            <p style="font-size:0.8rem;color:var(--text-light);margin-bottom:16px">We'll deliver your furniture soon!</p>
            <button onclick="toggleCart(); goHome();" class="btn btn-gold-sm">Continue Shopping</button>
        </div>`;
    document.getElementById('checkout-form').classList.add('hidden');
    document.getElementById('cart-footer').style.display = 'none';
    } catch(e) {
        console.error('Order error:', e);
        alert('Something went wrong. Please try again.');
    }
}

// --- Navigation ---
function goHome() {
    window.scrollTo({ top: 0, behavior: 'smooth' });
}
function showShop() {
    document.getElementById('shop').scrollIntoView({ behavior: 'smooth' });
}

// --- Toast ---
let toastTimeout;
function showToast() {
    clearTimeout(toastTimeout);
    toast.classList.remove('translate-y-24');
    toastTimeout = setTimeout(() => toast.classList.add('translate-y-24'), 2000);
}

// --- Navbar ---
const navbar = document.getElementById('navbar');
window.addEventListener('scroll', () => {
    navbar.classList.toggle('scrolled', window.scrollY > 50);
});

// Mobile nav
document.getElementById('nav-toggle').addEventListener('click', () => {
    document.getElementById('nav-links').classList.toggle('open');
});
document.querySelectorAll('.nav-link').forEach(l => {
    l.addEventListener('click', () => document.getElementById('nav-links').classList.remove('open'));
});

// --- Intersection Observer ---
const observer = new IntersectionObserver((entries) => {
    entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('visible'); observer.unobserve(e.target); } });
}, { threshold: 0.1, rootMargin: '0px 0px -30px 0px' });
document.querySelectorAll('.fade-up').forEach(el => observer.observe(el));

// --- Smooth scroll anchors ---
document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', function (e) {
        const href = this.getAttribute('href');
        if (href !== '#') { e.preventDefault(); document.querySelector(href)?.scrollIntoView({ behavior: 'smooth' }); }
    });
});

// --- Init ---
fetchProducts();
renderCart();
