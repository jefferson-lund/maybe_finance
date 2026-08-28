# Transactions list

Open questions from using the live list. The goal is: every row shows a category, names stay short, and changing a category is one click when needed.

- [x] **Show a category on every row and make it easy to change.**  
  The list header has Transaction / Category / Amount, but many rows look like they have no category. The category control is currently hidden below the `lg` breakpoint (`hidden lg:flex` in `_transaction.html.erb`) while the header appears from `md`, so laptops and the in-app browser can show an empty Category column. The cell should always be visible at the same breakpoint as the header. The control should stay a one-click menu (already `categories/menu`) so a category can be changed only when needed, without opening the full transaction drawer.

- [x] **Shorten transaction names.**  
  Plaid and bank names overflow the Transaction column and crowd the Auto-matched controls. Constrain the name with a real truncate (`min-w-0` on the flex parent, single line, title/tooltip for the full string) so Amount and Category stay aligned.

- [x] **Stop treating Auto-matched as category approval.**  
  Auto-matched is a pending *transfer* match (two accounts, confirm or reject with the check/x). It is not a category suggestion, which is why only some rows have it. Relabel it as a transfer match (for example "Possible transfer") and keep confirm/reject next to that label. Categories should be set on every non-transfer row—Uncategorized is a real state you can change from the list, not an empty cell.
