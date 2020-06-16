/// Copyright (c) 2019 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import CoreML
import Vision

class ViewController: UIViewController {
    
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var cameraButton: UIButton!
    @IBOutlet var photoLibraryButton: UIButton!
    @IBOutlet var resultsView: UIView!
    @IBOutlet var resultsLabel: UILabel!
    @IBOutlet var resultsConstraint: NSLayoutConstraint!
    
    // lazy: 只要當第一次被呼叫才會執行, 之後就會重複利用
    lazy var classificationRequest: VNCoreMLRequest = {
        do {
            // HealthySnacks這是當把mlmodel拉到專案時，自動產生的class
            let healthySnacks = HealthySnacks()
            // 建立pipeline, 將CoreML跟Vision產生連結
            let visionModel = try VNCoreMLModel(for: healthySnacks.model)
            // 這個request很重要，負擔大量的工作
            // 1. 將傳入的image轉成CVPixelBuffer
            // 2. 將大小切割成227×227
            // 3. 將方向進行調整
            let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                self?.processObservations(for: request, error: error)
            }
            request.imageCropAndScaleOption = .centerCrop
            return request
        } catch {
            // 讀取到無效的mlmodel
            fatalError("無法產生 VNCoreMLModel: \(error)")
        }
    }()
    
    var firstTime = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        cameraButton.isEnabled = UIImagePickerController.isSourceTypeAvailable(.camera)
        resultsView.alpha = 0
        resultsLabel.text = "choose or take a photo"
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Show the "choose or take a photo" hint when the app is opened.
        if firstTime {
            showResultsView(delay: 0.5)
            firstTime = false
        }
    }
    
    @IBAction func takePicture() {
        presentPhotoPicker(sourceType: .camera)
    }
    
    @IBAction func choosePhoto() {
        presentPhotoPicker(sourceType: .photoLibrary)
    }
    
    func presentPhotoPicker(sourceType: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = sourceType
        present(picker, animated: true)
        hideResultsView()
    }
    
    func showResultsView(delay: TimeInterval = 0.1) {
        resultsConstraint.constant = 100
        view.layoutIfNeeded()
        
        UIView.animate(withDuration: 0.5,
                       delay: delay,
                       usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.6,
                       options: .beginFromCurrentState,
                       animations: {
                        self.resultsView.alpha = 1
                        self.resultsConstraint.constant = -10
                        self.view.layoutIfNeeded()
        },
                       completion: nil)
    }
    
    func hideResultsView() {
        UIView.animate(withDuration: 0.3) {
            self.resultsView.alpha = 0
        }
    }
    
    func classify(image: UIImage) {
        // 將UIImage轉成CIImage
        guard let ciImage = CIImage(image: image) else {
            print("無法產生CIImage")
            return
        }
        // 很重要: 取得目前圖片的方向, 之後Vision才有辦法做正確的轉向
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        // 將圖片轉換成model所需要的input, 讓model在背景執行運算
        DispatchQueue.global(qos: .userInitiated).async {
            let hadler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
            do {
                // perform傳入是一個array, 所以我們可以同時執行多個vision request
                try hadler.perform([self.classificationRequest])
            } catch {
                print("無法執行classification: \(error)")
            }
        }
    }
    
    func processObservations(for request: VNRequest, error: Error?) {
        // 回到main queue執行對應的UI操作
        DispatchQueue.main.async {
            if let results = request.results as? [VNClassificationObservation] {
                // 成功: 但沒東西
                if results.isEmpty {
                    self.resultsLabel.text = "沒找到任何東西"
                } else if results[0].confidence < 0.8 {
                    // 成功: 找到東西, 但不確定
                    self.resultsLabel.text = "不確定"
                } else {
                    // 成功: 找到東西, 且確定
                    self.resultsLabel.text = String(format: "%@ %.1f%%", results[0].identifier, results[0].confidence * 100)
                }
            } else if let error = error {
                // 失敗: 錯誤原因
                self.resultsLabel.text = "錯誤: \(error.localizedDescription)"
            } else {
                // 未知狀況
                self.resultsLabel.text = "發生未知狀況"
            }
            self.showResultsView()
        }
    }
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        let image = info[.originalImage] as! UIImage
        imageView.image = image
        
        classify(image: image)
    }
}
