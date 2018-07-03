//
//  VoteViewController.swift
//  Wallet
//
//  Created by Maynard on 2018/5/8.
//  Copyright © 2018年 New Horizon Labs. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import UITableView_FDTemplateLayoutCell

class VoteViewController: UIViewController {

    @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var confirmView: VoteConfirmView!
    let disposeBag = DisposeBag()
    
    var data: Variable<[Witness]> = Variable([])
    var voteModelArray: [Vote] = []
    var isEdit: Bool = false {
        didSet {
            let constant: CGFloat = isEdit ? 10 : -100
            let alpha: CGFloat = isEdit ? 1.0 : 0.0
            UIView.animate(withDuration: 0.35) {
                self.confirmView.alpha = alpha
                self.bottomConstraint.constant = constant
            }
            confirmView.layoutIfNeeded()
            
        }
    }
    
    @IBOutlet weak var tableView: UITableView!
    override func viewDidLoad() {
        super.viewDidLoad()
        title = R.string.tron.voteNavTitle()
        tableView.register(R.nib.voteTableViewCell)
        tableView.delegate = self
        data.asObservable().bind(to: tableView.rx.items(cellIdentifier: R.nib.voteTableViewCell.identifier, cellType: VoteTableViewCell.self)) { index, model, cell in
            let voteArray = self.isEdit ? self.voteModelArray : ServiceHelper.shared.voteArray
            cell.configure(model: model, voteArray: voteArray)
        
            cell.numberLabel.text = "#\(index + 1)"
            }.disposed(by: disposeBag)
        
        loadData()
        tableView.addRefreshHeader {[weak self] in
            self?.loadData()
        }
        ServiceHelper.shared.voteChange.asObservable()
            .subscribe(onNext: {[weak self] (_) in
                ServiceHelper.shared.getAccount()
                self?.tableView.reloadData()
            })
        .disposed(by: disposeBag)
        
        ServiceHelper.shared.account.asObservable()
            .subscribe(onNext: {[weak self] (account) in
                self?.orderArray()
            })
        .disposed(by: disposeBag)
        
        ServiceHelper.shared.voteModelChange.asObservable()
            .subscribe(onNext: {[weak self] (vote) in
                self?.updateVoteModelArray(vote: vote)
            })
        .disposed(by: disposeBag)
        
//        ServiceHelper.shared.voteArrayChange.asObservable()
//            .subscribe(onNext: { (_) in
//
//            })
//        .disposed(by: disposeBag)
        
        confirmView.sureBlock = {
            self.requestVote()
        }
        
        confirmView.cancleBlock = {
            self.isEdit = false
            self.voteModelArray = ServiceHelper.shared.voteArray
            self.tableView.reloadData()
        }
    }
    
    func requestVote() {
        guard self.voteModelArray.count > 0 else {
            HUD.showText(text: "Nothing to Vote")
            return
        }
        guard let account = ServiceHelper.shared.account.value else {
            return
        }
        self.displayLoading()
        //投票数据
        let voteContractArray = self.voteModelArray.map { (model) -> VoteWitnessContract_Vote in
            let vote = VoteWitnessContract_Vote()
            vote.voteAddress = model.voteAddress
            vote.voteCount = model.voteCount
            return vote
        }
        
        //用户数据
        let contract = VoteWitnessContract()
        contract.ownerAddress = account.address
        contract.votesArray = NSMutableArray(array: voteContractArray)
        
        ServiceHelper.shared.service.voteWitnessAccount(withRequest: contract) { (transaction, error) in
            if let action = transaction {
                ServiceHelper.shared.broadcastTransaction(action, completion: { (result, error) in
                    if let response = result {
                        let result = response.result
                        if result {
                            self.isEdit = false
                            ServiceHelper.shared.voteChange.onNext(())
                            HUD.showText(text: R.string.tron.hudSuccess())
                        } else {
                            HUD.showError(error: "Vote Failed, If you don't have\n freeze TRX, please freeze TRX first")
                        }
                        
                    }
                    self.hideLoading()
                })
            } else if let error = error {
                self.hideLoading()
                HUD.showError(error: (error.localizedDescription))
            }
        }
    }
    
    func updateVoteModelArray(vote: Vote) {
        isEdit = true
        var filterArray = self.voteModelArray.filter { return $0.voteAddress.addressString != vote.voteAddress.addressString }
        if vote.voteCount <= 0 {
            self.voteModelArray = filterArray
        } else {
            filterArray.append(vote)
            self.voteModelArray = filterArray
        }
    }
    
    func orderArray() {
        let voteAddressArray = ServiceHelper.shared.voteArray.map { $0.voteAddress.addressString }
        var a1 = data.value.filter({ (object) -> Bool in
            return voteAddressArray.contains(object.address.addressString)
        })
        a1.sort { (w1, w2) -> Bool in
            let number1 = ServiceHelper.shared.voteArray.filter{ return w1.address.addressString == $0.voteAddress.addressString }.first?.voteCount
            let number2 = ServiceHelper.shared.voteArray.filter{ return w2.address.addressString == $0.voteAddress.addressString }.first?.voteCount
            guard let n1 = number1, let n2 = number2 else { return false }
            return n1 > n2
        }
        var a2 = data.value.filter({ (object) -> Bool in
            return !voteAddressArray.contains(object.address.addressString)
        })
        a2.sort { (w1, w2) -> Bool in
            return w1.voteCount > w2.voteCount
        }
        self.data.value = a1 + a2
    }
    
    func loadData() {
        displayLoading()
        ServiceHelper.shared.service.listWitnesses(withRequest: EmptyMessage()) {[weak self] (list, error) in
            let voteAddressArray = ServiceHelper.shared.voteArray.map { $0.voteAddress.addressString }
            if let array = list?.witnessesArray as? [Witness] {
                let a1 = array.filter({ (object) -> Bool in
                    return voteAddressArray.contains(object.address.addressString)
                })
                let a2 = array.filter({ (object) -> Bool in
                    return !voteAddressArray.contains(object.address.addressString)
                })
                self?.data.value = a1 + a2
                self?.orderArray()
            }
        
            self?.hideLoading()
            self?.tableView.endRefresh()
        }
    }

}

extension VoteViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let model = data.value[indexPath.row]
        return tableView.fd_heightForCell(withIdentifier: R.nib.voteTableViewCell.identifier, configuration: { (cell) in
            if let cell = cell as? VoteTableViewCell {
                let voteArray = self.isEdit ? self.voteModelArray : ServiceHelper.shared.voteArray
                cell.configure(model: model, voteArray: voteArray)
            }
        })
    }
}
