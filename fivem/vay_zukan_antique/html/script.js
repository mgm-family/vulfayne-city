(() => {
	const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'vay_zukan_antique';

	let sheets = [];
	let state = { Owned: {}, Claimed: {} };
	let activeSheetIndex = 0;

	const bookEl = document.getElementById('book');
	const categoryNameEl = document.getElementById('category-name');
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

	function isOwned(itemId) {
		return !!(state.Owned && state.Owned[itemId]);
	}

	function isClaimed(sheetIndex) {
		return !!(state.Claimed && state.Claimed[sheetIndex]);
	}

	function imagePath(itemId) {
		return `images/${itemId}.png`;
	}

	function applyTheme(category) {
		if (!category) return;
		categoryNameEl.textContent = category.CategoryName + ' 図鑑';
		document.documentElement.style.setProperty('--accent', category.ThemeColor);
		document.documentElement.style.setProperty('--accent-bright', category.ThemeColorBright);
	}

	function renderGrid() {
		const sheet = sheets[activeSheetIndex];
		if (!sheet) return;

		sheetTitleEl.textContent = `${sheet.Name} ― ${activeSheetIndex + 1} / ${sheets.length}`;

		let owned = 0;
		sheet.Items.forEach((item) => {
			if (isOwned(item.Id)) owned += 1;
		});

		if (owned >= sheet.Items.length) {
			sheetStatusEl.textContent = isClaimed(activeSheetIndex + 1)
				? `コンプリート！ 景品受け取り済み ― ${sheet.Reward.DisplayName}`
				: 'コンプリート！ NPCに話しかけて景品を受け取ろう';
		} else {
			sheetStatusEl.textContent = `${owned} / ${sheet.Items.length} 個登録済み`;
		}

		gridEl.innerHTML = '';
		sheet.Items.forEach((item) => {
			const owned = isOwned(item.Id);

			const slot = document.createElement('div');
			slot.className = 'slot ' + (owned ? 'unlocked' : 'locked');

			if (owned) {
				const image = document.createElement('div');
				image.className = 'slot-image';
				image.style.backgroundImage = `url('${imagePath(item.Id)}')`;
				slot.appendChild(image);
			} else {
				const mark = document.createElement('div');
				mark.className = 'slot-mark';
				mark.textContent = '？';
				slot.appendChild(mark);
			}

			const label = document.createElement('div');
			label.className = 'slot-label';
			label.textContent = owned ? item.Name : '？？？';
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
			modalDescEl.textContent = 'まだ登録されていない。マップのどこかに隠されている。';
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
		if (!sheets.length) return;
		activeSheetIndex = (activeSheetIndex - 1 + sheets.length) % sheets.length;
		renderGrid();
	});
	document.getElementById('next-button').addEventListener('click', () => {
		if (!sheets.length) return;
		activeSheetIndex = (activeSheetIndex + 1) % sheets.length;
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
			sheets = payload.sheets || [];
			state = payload.state || { Owned: {}, Claimed: {} };
			activeSheetIndex = 0;
			applyTheme(payload.category);
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
