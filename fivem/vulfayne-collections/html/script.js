(() => {
	const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'vulfayne-collections';

	let categories = [];
	let state = {};
	let activeCategoryIndex = 0;
	let activeSheetIndex = 0;

	const bookEl = document.getElementById('book');
	const tabsEl = document.getElementById('tabs');
	const gridEl = document.getElementById('grid');
	const sheetTitleEl = document.getElementById('sheet-title');
	const sheetStatusEl = document.getElementById('sheet-status');
	const modalEl = document.getElementById('modal');
	const modalCardEl = document.getElementById('modal-card');
	const modalImageEl = document.getElementById('modal-image');
	const modalNameEl = document.getElementById('modal-name');
	const modalDescEl = document.getElementById('modal-desc');

	function postNui(endpoint, data) {
		fetch(`https://${resourceName}/${endpoint}`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json; charset=UTF-8' },
			body: JSON.stringify(data || {}),
		}).catch(() => {});
	}

	function activeCategory() {
		return categories[activeCategoryIndex];
	}

	function isOwned(categoryId, itemId) {
		const cat = state[categoryId];
		return !!(cat && cat.Owned && cat.Owned[itemId]);
	}

	function isClaimed(categoryId, sheetIndex) {
		const cat = state[categoryId];
		return !!(cat && cat.Claimed && cat.Claimed[sheetIndex]);
	}

	function imagePath(itemId) {
		return `images/${itemId}.png`;
	}

	function renderTabs() {
		tabsEl.innerHTML = '';
		categories.forEach((cat, i) => {
			const btn = document.createElement('button');
			btn.className = 'tab-button' + (i === activeCategoryIndex ? ' active' : '');
			btn.textContent = cat.CategoryName;
			btn.addEventListener('click', () => {
				activeCategoryIndex = i;
				activeSheetIndex = 0;
				renderTabs();
				renderGrid();
			});
			tabsEl.appendChild(btn);
		});
	}

	function renderGrid() {
		const cat = activeCategory();
		if (!cat) return;
		const sheet = cat.Sheets[activeSheetIndex];

		sheetTitleEl.textContent = `${sheet.Name} ― ${activeSheetIndex + 1} / ${cat.Sheets.length}`;

		let owned = 0;
		sheet.Items.forEach((item) => {
			if (isOwned(cat.CategoryId, item.Id)) owned += 1;
		});

		if (owned >= sheet.Items.length) {
			sheetStatusEl.textContent = isClaimed(cat.CategoryId, activeSheetIndex + 1)
				? `コンプリート！ 景品受け取り済み ― ${sheet.Reward.DisplayName}`
				: 'コンプリート！ NPCに話しかけて景品を受け取ろう';
		} else {
			sheetStatusEl.textContent = `${owned} / ${sheet.Items.length} 個収集済み`;
		}

		gridEl.innerHTML = '';
		sheet.Items.forEach((item) => {
			const owned = isOwned(cat.CategoryId, item.Id);

			const slot = document.createElement('div');
			slot.className = 'slot' + (owned ? ' owned' : '');

			const image = document.createElement('div');
			image.className = 'slot-image';
			if (owned) {
				image.style.backgroundImage = `url('${imagePath(item.Id)}')`;
			}

			const label = document.createElement('div');
			label.className = 'slot-label';
			label.textContent = owned ? item.Name : '？？？';

			slot.appendChild(image);
			slot.appendChild(label);
			slot.addEventListener('click', () => openModal(item, owned));
			gridEl.appendChild(slot);
		});
	}

	function openModal(item, owned) {
		if (owned) {
			modalImageEl.style.backgroundImage = `url('${imagePath(item.Id)}')`;
			modalNameEl.textContent = item.Name;
			modalDescEl.textContent = item.Description;
		} else {
			modalImageEl.style.backgroundImage = '';
			modalNameEl.textContent = '？？？';
			modalDescEl.textContent = 'まだ手に入れていない。マップのどこかに隠されている。';
		}
		modalEl.classList.remove('hidden');
	}

	function closeModal() {
		modalEl.classList.add('hidden');
	}

	function closeBook() {
		bookEl.classList.add('hidden');
		closeModal();
		postNui('close');
	}

	document.getElementById('close-button').addEventListener('click', closeBook);
	document.getElementById('modal-close').addEventListener('click', closeModal);
	document.getElementById('prev-button').addEventListener('click', () => {
		const cat = activeCategory();
		if (!cat) return;
		activeSheetIndex = (activeSheetIndex - 1 + cat.Sheets.length) % cat.Sheets.length;
		renderGrid();
	});
	document.getElementById('next-button').addEventListener('click', () => {
		const cat = activeCategory();
		if (!cat) return;
		activeSheetIndex = (activeSheetIndex + 1) % cat.Sheets.length;
		renderGrid();
	});
	modalEl.addEventListener('click', (e) => {
		if (!modalCardEl.contains(e.target)) closeModal();
	});
	document.addEventListener('keydown', (e) => {
		if (e.key === 'Escape') {
			if (!modalEl.classList.contains('hidden')) {
				closeModal();
			} else if (!bookEl.classList.contains('hidden')) {
				closeBook();
			}
		}
	});

	window.addEventListener('message', (event) => {
		const payload = event.data;
		if (!payload || !payload.action) return;

		if (payload.action === 'open') {
			categories = payload.categories || [];
			state = payload.state || {};
			activeCategoryIndex = 0;
			activeSheetIndex = 0;
			renderTabs();
			renderGrid();
			bookEl.classList.remove('hidden');
		} else if (payload.action === 'close') {
			bookEl.classList.add('hidden');
			closeModal();
		} else if (payload.action === 'state') {
			state = payload.state || state;
			if (!bookEl.classList.contains('hidden')) {
				renderGrid();
			}
		}
	});
})();
