use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName, PolicyId}
use common/time.{BasisPoints, EpochConfig, SlotConfig}
use common/types.{ScriptKeyHash}

pub type RequestDatum {
  // Borrower Interest Rate: Phần trăm (%) lãi đề xuất theo năm người vay trả
  // noted: unit by basis point
  apr: Int,
  // Bond Duration: Chu kỳ đáo hạn khoản vay mỗi khi Danogo Bond được lender buy từ Borrow Request của người vay
  // noted: unit by epoch time
  duration: Int,
  // Policy Id của Danogo Borrow Request.
  symbol: PolicyId,
  // Danogo Borrow Request Borrower NFT token name tương ứng với Borrow Request trả cho ví tạo Borrow Request.
  // Sử dụng để xác định chủ sở hữu của Borrow Request khi muốn thực hiện update.
  borrower: AssetName,
  // Tổng số Danogo Bond đề xuất vay của Borrow Request.
  //  Giá trị này chỉ được điều chỉnh khi chủ sở hữu của đề xuất vay thực hiện cập nhật cấu hình của đề xuất vay.
  requested: Int,
  // Tổng số Danogo Bond đã phát hành và hình thành Bond (default = 0).
  // Giá trị này được update increment tương ứng số Danogo Bond token khi lender thực hiện khớp lệnh mua trên UI của Danogo Bond Exchanges.
  // Giá trị hiện hữu đại diện cho tổng số Danogo Bond token của Borrow Request đã được phát hành và hình thành các khoản vay hiện hữu tương ứng với số Danogo Bond token đó.
  issued: Int,
  // Min Epoch Rewards: Số tiền lãi tối thiểu trả cho mỗi epoch tương ứng với phần trăm lãi đề xuất theo năm người vay trả
  // noted: unit by lovelace
  epo_rewards: Int,
  // Required Premium: Số epoch lãi bảo hiểm khoản vay bắt buộc khi phát hành đề xuất vay
  // noted: unit by epoch time 
  prepaid: Int,
  // Thiêt lập giá trị số epoch lãi đệm tối thiểu mà khoản vay hình thành phải tuân thủ để không vi phạm về điều khoản
  // đảm bảo số epoch lãi tối thiểu để tránh bị thanh lý và cho phép người cho vay (Lender) được phép đóng vị thế
  // và rút tiền gốc + lãi (bao gồm cả số lãi bảo hiểm/lãi đệm còn lại trả trước khoản vay)
  // noted: unit by epoch time
  buffer: Int,
  // Phần trăm (%) tiền phí Danogo thu trên epo_rewards tương ứng số epoch được người vay trả lãi cho các Danogo Bond được mua bởi Lender
  // Tiền phí này được Danogo thu ngay khi hình thành khoản vay (Lender Bond Create) hoặc ngay khi giao dịch trả lãi (Lender Bond Pay Interest) cho khoản vay.
  // noted: unit by basis point
  //
  fee: Int,
}

pub type RequestAction {
  RequestCreate { sk: ScriptKeyHash }
  RequestUpdate
  RequestBondCreate
}

pub type RequestConfig {
  slot: SlotConfig,
  epoch: EpochConfig,
  basis_points: BasisPoints,
  platform: RequestPlatformConfig,
}

pub type RequestPlatformConfig {
  // 1 bond = 100 ADA = 100_000_000 lovelace. default: 100 ADA = 100_000_000 lovelace
  bond_face_value: Int,
  // value in range 0001 -> 9999 default: 500 (5%) per apr 
  fee: Int,
  // fee receive address
  address: Address,
  // Khoảng thời gian giao dịch hợp lệ, giá trị tính theo slot
  tx_ttl: Option<Int>,
  // default: 6 epoch
  min_buffer: Int,
  // datum.prepaid = Min(<min_buffer>+prepaid_plus, <duration>)
  prepaid_plus: Int,
  // default: 100 Bond = 10_000 ADA
  min_requested: Int,
  // default: 200 (2.00%)
  min_apr: Int,
  // default: 6 epoch
  min_duration: Int,
}
